"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.manageHeroApproval = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();
function userLooksAdmin(data) {
    if (!data) {
        return false;
    }
    return data['userType'] === 2 ||
        data['userType'] === 'admin' ||
        data['role'] === 'admin' ||
        data['admin'] === true ||
        data['isAdmin'] === true;
}
async function assertAdmin(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
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
    throw new functions.https.HttpsError('permission-denied', 'Admin privileges required');
}
exports.manageHeroApproval = functions.https.onCall(async (data, context) => {
    var _a;
    await assertAdmin(context);
    if (!data.heroId || (data.action !== 'approve' && data.action !== 'reject')) {
        throw new functions.https.HttpsError('invalid-argument', 'heroId and valid action are required');
    }
    const heroRef = db.collection('heroes').doc(data.heroId);
    const heroSnap = await heroRef.get();
    if (!heroSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Hero not found');
    }
    const heroData = (_a = heroSnap.data()) !== null && _a !== void 0 ? _a : {};
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    if (data.action === 'approve') {
        const captainRef = db.collection('captains').doc(data.heroId);
        await db.runTransaction(async (transaction) => {
            var _a, _b, _c, _d, _e, _f;
            transaction.update(heroRef, {
                approvalStatus: 'approved',
                approvedAt: timestamp,
                lastUpdated: timestamp,
            });
            transaction.set(captainRef, {
                uid: data.heroId,
                name: (_a = heroData['name']) !== null && _a !== void 0 ? _a : '',
                email: (_b = heroData['email']) !== null && _b !== void 0 ? _b : '',
                phone: (_c = heroData['phone']) !== null && _c !== void 0 ? _c : '',
                vehicleNumber: (_d = heroData['vehicleNumber']) !== null && _d !== void 0 ? _d : '',
                vehicleType: (_e = heroData['vehicleType']) !== null && _e !== void 0 ? _e : 'bike',
                licenseNumber: (_f = heroData['licenseNumber']) !== null && _f !== void 0 ? _f : '',
                isOnline: false,
                isVerified: true,
                approvalStatus: 'approved',
                approvedAt: timestamp,
                lastUpdated: timestamp,
            }, { merge: true });
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
});
//# sourceMappingURL=manageHeroApproval.js.map