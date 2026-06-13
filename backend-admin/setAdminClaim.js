const admin = require("firebase-admin");

// Service account key (to be added manually by developer)
const serviceAccount = require("./serviceAccountKey.json");

// 🔁 Developer will replace this
const ADMIN_EMAIL = "nijjam1993@gmail.com";

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

async function setAdminClaim() {
  try {
    const user = await admin.auth().getUserByEmail(ADMIN_EMAIL);

    await admin.auth().setCustomUserClaims(user.uid, {
      admin: true,
      role: "admin"
    });

    console.log(`✅ Admin claim set for ${ADMIN_EMAIL}`);
    console.log("⚠️ Re-login required for token refresh");
    process.exit(0);
  } catch (error) {
    console.error("❌ Error:", error);
    process.exit(1);
  }
}

setAdminClaim();
