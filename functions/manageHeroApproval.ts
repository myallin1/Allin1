import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

interface HeroApprovalRequest {
  heroId: string;
  action: 'approve' | 'reject';
}

function userLooksAdmin(data: FirebaseFirestore.DocumentData | undefined): boolean {
  if (!data) {
    return false;
  }

  return data['userType'] === 2 ||
      data['userType'] === 'admin' ||
      data['role'] === 'admin' ||
      data['admin'] === true ||
      data['isAdmin'] === true;
}

async function assertAdmin(context: functions.https.CallableContext): Promise<void> {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated',
    );
  }

  if (context.auth.token.admin === true || context.auth.token.role === 'admin') {
    return;
  }

  const uid = context.auth.uid;
  const [adminDoc, userDoc] = await Promise.all([
    db.collection('admins').doc(uid).get(),
    db.collection('users').doc(uid).get(),
  ]);

  if (adminDoc.exists || userLooksAdmin(userDoc.data())) {
    return;
  }

  throw new functions.https.HttpsError(
    'permission-denied',
    'Admin privileges required',
  );
}

export const manageHeroApproval = functions.https.onCall(
  async (data: HeroApprovalRequest, context) => {
    await assertAdmin(context);

    if (!data.heroId || (data.action !== 'approve' && data.action !== 'reject')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'heroId and valid action are required',
      );
    }

    const heroRef = db.collection('heroes').doc(data.heroId);
    const heroSnap = await heroRef.get();

    if (!heroSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Hero not found');
    }

    const heroData = heroSnap.data() ?? {};
    const timestamp = admin.firestore.FieldValue.serverTimestamp();

    if (data.action === 'approve') {
      const captainRef = db.collection('captains').doc(data.heroId);

      await db.runTransaction(async (transaction) => {
        transaction.update(heroRef, {
          approvalStatus: 'approved',
          approvedAt: timestamp,
          lastUpdated: timestamp,
        });

        transaction.set(
          captainRef,
          {
            uid: data.heroId,
            name: heroData['name'] ?? '',
            email: heroData['email'] ?? '',
            phone: heroData['phone'] ?? '',
            vehicleNumber: heroData['vehicleNumber'] ?? '',
            vehicleType: heroData['vehicleType'] ?? 'bike',
            licenseNumber: heroData['licenseNumber'] ?? '',
            isOnline: false,
            isVerified: true,
            approvalStatus: 'approved',
            approvedAt: timestamp,
            lastUpdated: timestamp,
          },
          {merge: true},
        );
      });

      return {
        'success': true,
        'status': 'approved',
      };
    }

    await heroRef.update({
      approvalStatus: 'rejected',
      rejectedAt: timestamp,
      lastUpdated: timestamp,
    });

    return {
      'success': true,
      'status': 'rejected',
    };
  },
);
