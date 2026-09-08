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
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.db = void 0;
exports.requireAuth = requireAuth;
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
/**
 * Verifies the Firebase ID token attached by DioClient's interceptor
 * (see lib/core/network/dio_client.dart) and returns the decoded token,
 * or writes a 401 and returns null.
 *
 * Every CJ Dropshipping / IntaSend proxy function should call this
 * first — it's the only thing standing between "anyone on the internet"
 * and your CJ/IntaSend secret keys.
 */
async function requireAuth(req, res) {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) {
        res.status(401).json({ message: 'Missing Authorization header' });
        return null;
    }
    try {
        return await admin.auth().verifyIdToken(token);
    }
    catch (err) {
        res.status(401).json({ message: 'Invalid or expired session' });
        return null;
    }
}
exports.db = admin.firestore();
//# sourceMappingURL=auth.js.map