import {initializeApp, cert, deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';

const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is missing.');
const serviceAccount = JSON.parse(raw);
const projectId = process.env.FIREBASE_PROJECT_ID || serviceAccount.project_id;
const userId = String(process.env.SMOKE_DELETE_USER_ID || '').trim();
const requestId = String(process.env.SMOKE_DELETE_REQUEST_ID || '').trim();
if (!userId || !requestId) throw new Error('Smoke deletion identifiers are missing.');

const app = initializeApp({credential: cert(serviceAccount), projectId}, 'smokeDeletionVerifier');
const auth = getAuth(app);
const db = getFirestore(app);
const userRef = db.collection('users').doc(userId);
const requestRef = db.collection('admin_requests').doc(requestId);

let verificationError;
try {
  const [profile, request] = await Promise.all([userRef.get(), requestRef.get()]);
  let authExists = true;
  try {
    await auth.getUser(userId);
  } catch (error) {
    if (error?.code === 'auth/user-not-found') authExists = false;
    else throw error;
  }

  if (profile.exists) throw new Error('GitHub deletion worker left the Firestore user profile.');
  if (authExists) throw new Error('GitHub deletion worker left the Firebase Authentication account.');
  if (!request.exists || request.data()?.status !== 'completed') {
    throw new Error(`Deletion request was not completed: ${request.data()?.status ?? 'missing'}`);
  }
  console.log('PASS verified: GitHub permanently deleted the Firebase Auth account and Firestore profile.');
} catch (error) {
  verificationError = error;
} finally {
  // Test-only cleanup so smoke data never remains in production.
  try { await userRef.delete(); } catch (_) {}
  try { await auth.deleteUser(userId); } catch (error) {
    if (error?.code !== 'auth/user-not-found') console.error(`Auth cleanup failed: ${error}`);
  }
  try {
    const audits = await db.collection('audit')
      .where('targetId', '==', userId)
      .limit(20)
      .get();
    for (const doc of audits.docs) {
      if (String(doc.data()?.operation ?? '').includes('DELETE_USER')) {
        await doc.ref.delete().catch(() => undefined);
      }
    }
  } catch (error) {
    console.error(`Audit cleanup failed: ${error}`);
  }
  try { await requestRef.delete(); } catch (_) {}
  await deleteApp(app);
}
if (verificationError) throw verificationError;
