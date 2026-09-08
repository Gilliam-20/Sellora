import * as admin from 'firebase-admin';
import { Request, Response } from 'firebase-functions';

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
export async function requireAuth(req: Request, res: Response): Promise<admin.auth.DecodedIdToken | null> {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    res.status(401).json({ message: 'Missing Authorization header' });
    return null;
  }

  try {
    return await admin.auth().verifyIdToken(token);
  } catch (err) {
    res.status(401).json({ message: 'Invalid or expired session' });
    return null;
  }
}

export const db = admin.firestore();
