// ================================================================
// hero_presence_utils.dart — DEPRECATED, unused.
// ================================================================
// This file backed a heartbeat/staleness-based presence check that
// was reverted per CTO architecture decision: presence is governed
// entirely by RTDB's onDisconnect() + a `.info/connected` reconnect
// watcher (see hero_home_screen.dart's _startPresenceConnectionWatcher),
// with no client heartbeat writes and no admin-side staleness timeout.
// Nothing in the codebase imports this file anymore. Left in place
// (rather than needing a delete) only because this tooling can't
// remove files from the repo directly — safe to delete manually.
// ================================================================
