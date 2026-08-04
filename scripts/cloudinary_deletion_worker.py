#!/usr/bin/env python3
"""
cloudinary_deletion_worker.py — Allin1 "WhatsApp Model" cleanup worker
========================================================================
Runs on Nizam's own backend/local server (NOT Firebase Cloud Functions —
deliberately avoided so the project stays on the free Spark plan, no
Blaze billing needed). Watches Firestore's `service_requests` collection
in real time and, the moment a grocery_order finishes (status ->
'completed'), permanently deletes that order's uploaded DMart-cart
screenshots from Cloudinary.

WHY THIS EXISTS (per Nizam/CTO's "WhatsApp Model" philosophy):
  - Cloud storage should only be a transient bridge, not a permanent
    archive: once the hero has fulfilled the order using the uploaded
    screenshots, there is no further need to keep those images on
    Cloudinary. Deleting them the moment the order completes keeps
    Cloudinary's free-tier 25GB storage/bandwidth budget reusable
    indefinitely instead of filling up with fulfilled orders.
  - The order's TEXT details (list text, address, status history, etc.)
    already live in Firestore and are cached locally on the customer's
    device by the Flutter app's normal Firestore offline persistence —
    nothing about that changes here. This worker only ever touches the
    heavy image URLs, and only after the order is fully done.

SECURITY (why this must NOT run inside the Flutter app):
  Cloudinary's delete/destroy API must be signed with your API secret.
  That secret can never be shipped inside a Flutter app (customer/hero/
  admin APKs are trivially decompiled and any embedded secret is
  extracted in minutes). This script is the one place that secret is
  allowed to exist, and even here it's read from an environment
  variable / .env file, never hardcoded — see CONFIGURATION below.

WHAT IT DOES, IN ORDER:
  1. On startup, does one reconciliation pass over any grocery_order
     docs that are ALREADY 'completed' but haven't been cleaned up yet
     (covers orders that completed while this worker was offline).
  2. Then attaches a live Firestore snapshot listener on
     `service_requests` (filtered to requestType == 'grocery_order' and
     status == 'completed') so every future completion is caught the
     moment it happens, no polling delay.
  3. For each such order: reads `details.listImageUrls` (falls back to
     the older singular `details.listImageUrl` for orders placed before
     the multi-image feature shipped), derives each image's Cloudinary
     `public_id` straight from its secure_url (no Flutter-side change
     needed — see `_public_id_from_url` below), and calls Cloudinary's
     `uploader.destroy()` for each one.
  4. Marks the order `details.cloudinaryImagesDeleted = True` and
     clears `details.listImageUrls`/`details.listImageUrl` in Firestore
     itself too, so the heavy URL strings don't linger in your Firestore
     document forever either — genuinely transient, not just on
     Cloudinary's side.
  5. Never reprocesses an order twice: the `cloudinaryImagesDeleted`
     flag from step 4 is checked before doing any deletion work, both
     in the startup reconciliation pass and in the live listener (the
     live listener alone would otherwise fire again on step 4's own
     write, since it's a write to a doc matching the same query).

CONFIGURATION (all via environment variables — nothing secret is
hardcoded in this file, so it's safe to commit):
  FIREBASE_SERVICE_ACCOUNT_PATH   Path to your Firebase service account
                                   JSON key (Firebase Console -> Project
                                   Settings -> Service Accounts ->
                                   Generate new private key). Keep this
                                   file OUT of git.
  CLOUDINARY_CLOUD_NAME           Same cloud name already used in
                                   lib/services/cloudinary_upload_service.dart
                                   (currently 'qx5zvm4w').
  CLOUDINARY_API_KEY              From Cloudinary Console -> Settings ->
                                   API Keys. Safe-ish (not secret) but
                                   still best kept out of source control.
  CLOUDINARY_API_SECRET           From the same page. THE thing this
                                   whole script exists to keep off the
                                   client. Never commit this.

USAGE:
  pip install firebase-admin cloudinary
  export FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccountKey.json
  export CLOUDINARY_CLOUD_NAME=qx5zvm4w
  export CLOUDINARY_API_KEY=xxxxxxxxxxxxxxx
  export CLOUDINARY_API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxx
  python3 cloudinary_deletion_worker.py

  Run it as a persistent background service (systemd unit, pm2, tmux,
  Windows Task Scheduler + `pythonw`, whatever Nizam's server already
  uses for the other Python automation scripts) — it's a long-running
  process, not a one-shot script.
========================================================================
"""

from __future__ import annotations

import logging
import os
import re
import signal
import sys
import threading
import time
from typing import Any

try:
    import cloudinary
    import cloudinary.uploader
except ImportError:
    print(
        "Missing dependency 'cloudinary'. Install with:\n"
        "    pip install cloudinary\n",
        file=sys.stderr,
    )
    raise

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    from google.cloud.firestore_v1 import FieldFilter
    from google.cloud.firestore_v1.base_query import BaseCompositeFilter  # noqa: F401
except ImportError:
    print(
        "Missing dependency 'firebase-admin'. Install with:\n"
        "    pip install firebase-admin\n",
        file=sys.stderr,
    )
    raise


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("cloudinary_deletion_worker")

COLLECTION_NAME = "service_requests"
REQUEST_TYPE = "grocery_order"
COMPLETED_STATUS = "completed"

# Matches the standard Cloudinary secure_url shape:
#   https://res.cloudinary.com/<cloud>/image/upload/v<digits>/<public_id>.<ext>
# <public_id> may itself contain slashes (folder path, e.g.
# 'service_request_images/<uid>/<requestId>/<randomId>') — captured
# whole, extension stripped. No Flutter-side change was needed for
# this: CloudinaryUploadService already uploads into a 'folder' field,
# Cloudinary's own auto-generated public_id just wasn't being saved
# back into Firestore, so we recover it from the URL it DID save.
_PUBLIC_ID_RE = re.compile(r"/upload/v\d+/(?P<public_id>.+?)\.[a-zA-Z0-9]+(?:\?.*)?$")


def _public_id_from_url(url: str) -> str | None:
    match = _PUBLIC_ID_RE.search(url)
    if not match:
        log.warning("Could not derive Cloudinary public_id from URL: %s", url)
        return None
    return match.group("public_id")


def _image_urls_from_details(details: dict[str, Any]) -> list[str]:
    """Same 'new field, old-field fallback' contract as the Flutter side's
    orderPhotoUrlsFromDetails() in lib/widgets/order_photo_gallery.dart —
    keep these two in sync if that ever changes."""
    urls = details.get("listImageUrls")
    if isinstance(urls, list):
        return [u for u in urls if isinstance(u, str) and u]
    single = details.get("listImageUrl")
    if isinstance(single, str) and single:
        return [single]
    return []


class CloudinaryDeletionWorker:
    def __init__(self) -> None:
        self._db = self._init_firestore()
        self._init_cloudinary()
        # Guards against the live listener and the startup reconciliation
        # pass (or two rapid listener callbacks for the same doc, which
        # Firestore's SDK can legitimately deliver) both trying to
        # process the same order at once.
        self._processing_lock = threading.Lock()
        self._in_flight: set[str] = set()
        self._stop_event = threading.Event()

    @staticmethod
    def _init_firestore():
        cred_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_PATH")
        if not cred_path:
            log.error(
                "FIREBASE_SERVICE_ACCOUNT_PATH is not set. See the module "
                "docstring's CONFIGURATION section."
            )
            sys.exit(1)
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        return firestore.client()

    @staticmethod
    def _init_cloudinary() -> None:
        cloud_name = os.environ.get("CLOUDINARY_CLOUD_NAME")
        api_key = os.environ.get("CLOUDINARY_API_KEY")
        api_secret = os.environ.get("CLOUDINARY_API_SECRET")
        missing = [
            name
            for name, val in (
                ("CLOUDINARY_CLOUD_NAME", cloud_name),
                ("CLOUDINARY_API_KEY", api_key),
                ("CLOUDINARY_API_SECRET", api_secret),
            )
            if not val
        ]
        if missing:
            log.error(
                "Missing required Cloudinary env vars: %s. See the module "
                "docstring's CONFIGURATION section.",
                ", ".join(missing),
            )
            sys.exit(1)
        cloudinary.config(
            cloud_name=cloud_name,
            api_key=api_key,
            api_secret=api_secret,
            secure=True,
        )

    # ------------------------------------------------------------------
    # Core deletion logic — shared by the startup reconciliation pass
    # and the live listener callback.
    # ------------------------------------------------------------------
    def _process_completed_order(self, doc_id: str, data: dict[str, Any]) -> None:
        details = data.get("details") or {}
        if details.get("cloudinaryImagesDeleted") is True:
            return  # already cleaned up, nothing to do

        with self._processing_lock:
            if doc_id in self._in_flight:
                return
            self._in_flight.add(doc_id)

        try:
            image_urls = _image_urls_from_details(details)
            if not image_urls:
                # No screenshots on this order at all (customer only used
                # the text list field) — still mark it so future listener
                # events for this doc short-circuit immediately above.
                self._mark_deleted(doc_id, deleted_count=0)
                return

            deleted = 0
            failed: list[str] = []
            for url in image_urls:
                public_id = _public_id_from_url(url)
                if not public_id:
                    failed.append(url)
                    continue
                if self._destroy_with_retry(public_id):
                    deleted += 1
                else:
                    failed.append(url)

            if failed:
                # Partial failure: mark what succeeded, but do NOT set
                # cloudinaryImagesDeleted, so the next reconciliation
                # pass or listener event retries the remaining ones
                # instead of silently giving up on them.
                log.error(
                    "Order %s: %d/%d screenshots deleted, %d failed: %s",
                    doc_id, deleted, len(image_urls), len(failed), failed,
                )
            else:
                self._mark_deleted(doc_id, deleted_count=deleted)
                log.info(
                    "Order %s: deleted %d screenshot(s) from Cloudinary, "
                    "cleared from Firestore.",
                    doc_id, deleted,
                )
        finally:
            with self._processing_lock:
                self._in_flight.discard(doc_id)

    def _destroy_with_retry(self, public_id: str, attempts: int = 2) -> bool:
        for attempt in range(1, attempts + 1):
            try:
                result = cloudinary.uploader.destroy(public_id, resource_type="image")
                # Cloudinary returns {'result': 'ok'} on success, or
                # {'result': 'not found'} if it's already gone — both
                # count as "this image is no longer on Cloudinary",
                # which is exactly the outcome we want either way.
                if result.get("result") in ("ok", "not found"):
                    return True
                log.warning(
                    "Cloudinary destroy(%s) attempt %d/%d unexpected result: %s",
                    public_id, attempt, attempts, result,
                )
            except Exception as e:  # noqa: BLE001 — log and retry/fail, don't crash the worker
                log.warning(
                    "Cloudinary destroy(%s) attempt %d/%d raised: %s",
                    public_id, attempt, attempts, e,
                )
            if attempt < attempts:
                time.sleep(1.5)
        return False

    def _mark_deleted(self, doc_id: str, *, deleted_count: int) -> None:
        doc_ref = self._db.collection(COLLECTION_NAME).document(doc_id)
        doc_ref.update({
            "details.cloudinaryImagesDeleted": True,
            "details.cloudinaryImagesDeletedCount": deleted_count,
            "details.cloudinaryImagesDeletedAt": firestore.SERVER_TIMESTAMP,
            # WhatsApp-model: wipe the heavy URL fields out of Firestore
            # too, not just off Cloudinary — the order's text details
            # stay, the image links (now dead anyway) don't linger.
            "details.listImageUrls": firestore.DELETE_FIELD,
            "details.listImageUrl": firestore.DELETE_FIELD,
        })

    # ------------------------------------------------------------------
    # Startup reconciliation — catches orders that completed while this
    # worker wasn't running (a live listener alone can't see the past).
    # ------------------------------------------------------------------
    def _run_reconciliation_pass(self) -> None:
        log.info("Running startup reconciliation pass...")
        query = (
            self._db.collection(COLLECTION_NAME)
            .where(filter=FieldFilter("requestType", "==", REQUEST_TYPE))
            .where(filter=FieldFilter("status", "==", COMPLETED_STATUS))
        )
        count = 0
        for doc in query.stream():
            self._process_completed_order(doc.id, doc.to_dict() or {})
            count += 1
        log.info("Reconciliation pass done — checked %d completed grocery order(s).", count)

    # ------------------------------------------------------------------
    # Live listener — catches every future completion in real time.
    # ------------------------------------------------------------------
    def _on_snapshot(self, docs, changes, read_time) -> None:  # noqa: ANN001 — firestore callback signature
        for change in changes:
            if change.type.name in ("ADDED", "MODIFIED"):
                doc = change.document
                self._process_completed_order(doc.id, doc.to_dict() or {})

    def run(self) -> None:
        self._run_reconciliation_pass()

        query = (
            self._db.collection(COLLECTION_NAME)
            .where(filter=FieldFilter("requestType", "==", REQUEST_TYPE))
            .where(filter=FieldFilter("status", "==", COMPLETED_STATUS))
        )
        watch = query.on_snapshot(self._on_snapshot)
        log.info(
            "Listening for completed grocery orders on '%s' (requestType='%s', "
            "status='%s')... Ctrl+C to stop.",
            COLLECTION_NAME, REQUEST_TYPE, COMPLETED_STATUS,
        )

        def _handle_signal(signum, frame):  # noqa: ANN001
            log.info("Shutdown signal received, stopping watch...")
            self._stop_event.set()

        signal.signal(signal.SIGINT, _handle_signal)
        signal.signal(signal.SIGTERM, _handle_signal)

        try:
            while not self._stop_event.is_set():
                time.sleep(1)
        finally:
            watch.unsubscribe()
            log.info("Stopped.")


def main() -> None:
    worker = CloudinaryDeletionWorker()
    worker.run()


if __name__ == "__main__":
    main()
