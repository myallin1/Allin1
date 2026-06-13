"use strict";
/**
 * ================================================================
 * Cloud Function: checkDeviceFingerprint
 * Purpose: Prevent device farming (same device, multiple accounts)
 * ================================================================
 *
 * SECURITY RULE:
 * Before allowing a user to start a task, check if the current deviceId
 * has already completed this taskId on ANY other account. If yes, BLOCK.
 */
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
exports.registerDevice = exports.checkDeviceFingerprint = void 0;
const functions = __importStar(require("firebase-functions"));
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
const db = admin.firestore();
exports.checkDeviceFingerprint = functions.https.onCall(async (data, context) => {
    // ── AUTH CHECK ──────────────────────────────────────────────
    if (!context.auth) {
        return {
            allowed: false,
            message: 'User must be authenticated',
            errorCode: 'UNAUTHENTICATED',
        };
    }
    // Verify user is calling for themselves
    if (context.auth.uid !== data.userId) {
        return {
            allowed: false,
            message: 'Users can only check their own device',
            errorCode: 'UNAUTHORIZED',
        };
    }
    // ── INPUT VALIDATION ────────────────────────────────────────
    if (!data.deviceId || !data.taskId) {
        return {
            allowed: false,
            message: 'Device ID and Task ID are required',
            errorCode: 'INVALID_INPUT',
        };
    }
    try {
        // ── DEVICE FARMING CHECK (THE CRITICAL SECURITY CHECK) ───
        // Query: Find all completions of this taskId from this deviceId
        // across ANY user account
        const completionsQuery = await db.collection('task_completions')
            .where('taskId', '==', data.taskId)
            .where('deviceId', '==', data.deviceId)
            .where('coinStatus', 'in', ['verified', 'pending'])
            .get();
        if (!completionsQuery.empty) {
            // Device has already completed this task on another account
            const existingCompletions = completionsQuery.size;
            firebase_functions_1.logger.warn(`Device farming detected: Device ${data.deviceId} attempted task ${data.taskId} on user ${data.userId}. ` +
                `Already completed ${existingCompletions} times on other accounts.`);
            return {
                allowed: false,
                message: `This task has already been completed on this device (${existingCompletions} times). Device farming is not allowed.`,
                errorCode: 'DEVICE_FARMING_DETECTED',
                existingCompletions: existingCompletions,
            };
        }
        // ── ADDITIONAL CHECK: Same device, different user ─────────
        // Check if this deviceId is associated with other user accounts
        const deviceUsersQuery = await db.collection('users')
            .where('deviceId', 'array-contains', data.deviceId)
            .get();
        const associatedUsers = deviceUsersQuery.docs.map(doc => doc.id);
        // If device is associated with multiple users, flag for review
        if (associatedUsers.length > 1 && !associatedUsers.includes(data.userId)) {
            firebase_functions_1.logger.warn(`Device shared across accounts: Device ${data.deviceId} is associated with ` +
                `users: ${associatedUsers.join(', ')}`);
            // Still allow, but flag for manual review
            await db.collection('users').doc(data.userId).update({
                flaggedForReview: true,
                reviewReason: `Device ${data.deviceId} shared across ${associatedUsers.length} accounts`,
            });
        }
        // ── REGISTER DEVICE TO USER ───────────────────────────────
        // Add this deviceId to user's device array (if not already present)
        const userRef = db.collection('users').doc(data.userId);
        const userDoc = await userRef.get();
        if (userDoc.exists) {
            const userData = userDoc.data();
            const existingDevices = userData.deviceIds || [];
            if (!existingDevices.includes(data.deviceId)) {
                await userRef.update({
                    deviceIds: admin.firestore.FieldValue.arrayUnion(data.deviceId),
                });
            }
        }
        firebase_functions_1.logger.info(`Device check passed: User ${data.userId}, Device ${data.deviceId}, Task ${data.taskId}`);
        return {
            allowed: true,
            message: 'Device check passed',
        };
    }
    catch (error) {
        firebase_functions_1.logger.error('Device fingerprint check failed:', error);
        return {
            allowed: false,
            message: 'Device check failed',
            errorCode: 'CHECK_ERROR',
        };
    }
});
/**
 * ================================================================
 * Helper: Register Device to User
 * Call this on app install/first login
 * ================================================================
 */
exports.registerDevice = functions.https.onCall(async (data, context) => {
    if (!context.auth || context.auth.uid !== data.userId) {
        return { success: false, message: 'Unauthorized' };
    }
    await admin.firestore().collection('users').doc(data.userId).update({
        deviceIds: admin.firestore.FieldValue.arrayUnion(data.deviceId),
        lastDeviceId: data.deviceId,
        lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, message: 'Device registered' };
});
//# sourceMappingURL=checkDeviceFingerprint.js.map