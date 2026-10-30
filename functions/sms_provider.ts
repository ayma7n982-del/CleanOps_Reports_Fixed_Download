import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { HttpsError } from 'firebase-functions/v2/https';

// SMS credentials are never stored in Firestore, client preferences, or source.
const secretClient = new SecretManagerServiceClient();
const names = {
  accountSid: 'CLEANOPS_TWILIO_ACCOUNT_SID',
  authToken: 'CLEANOPS_TWILIO_AUTH_TOKEN',
  from: 'CLEANOPS_TWILIO_FROM',
} as const;

export interface SmsCredentials {
  accountSid: string;
  authToken: string;
  from: string;
}

async function secretParent(): Promise<string> {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT ||
      await secretClient.getProjectId();
  if (!projectId) throw new HttpsError('failed-precondition', 'Firebase project is not configured.');
  return `projects/${projectId}`;
}

async function readSecret(secretId: string): Promise<string> {
  const parent = await secretParent();
  const [version] = await secretClient.accessSecretVersion({
    name: `${parent}/secrets/${secretId}/versions/latest`,
  });
  const payload = version.payload?.data;
  return payload ? Buffer.from(payload as Uint8Array).toString('utf8') : '';
}

export async function readSmsCredentials(): Promise<SmsCredentials> {
  try {
    const [accountSid, authToken, from] = await Promise.all([
      readSecret(names.accountSid),
      readSecret(names.authToken),
      readSecret(names.from),
    ]);
    if (!accountSid || !authToken || !from) {
      throw new HttpsError('failed-precondition', 'SMS provider is not configured.');
    }
    return { accountSid, authToken, from };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    const code = (error as { code?: number })?.code;
    if (code === 5) {
      throw new HttpsError('failed-precondition', 'SMS provider is not configured.');
    }
    if (code === 7) {
      throw new HttpsError('failed-precondition', 'Secret Manager access is not authorized for the Firebase server.');
    }
    throw new HttpsError('unavailable', 'SMS provider configuration cannot be verified right now.');
  }
}

export async function smsProviderStatus(): Promise<{ready: boolean; sender: string; reason: string}> {
  try {
    const credentials = await readSmsCredentials();
    return {
      ready: true,
      sender: credentials.from.replace(/.(?=.{4})/g, '•'),
      reason: '',
    };
  } catch (e) {
    return {
      ready: false,
      sender: '',
      reason: e instanceof HttpsError && e.code === 'failed-precondition'
        ? 'setup-required' : 'temporarily-unavailable',
    };
  }
}

async function writeSecret(secretId: string, value: string): Promise<void> {
  const parent = await secretParent();
  const secretPath = `${parent}/secrets/${secretId}`;
  const appendVersion = () => secretClient.addSecretVersion({
    parent: secretPath,
    payload: {data: Buffer.from(value, 'utf8')},
  });
  try {
    // Existing secrets require only Secret Version Adder, not project-wide
    // Secret Manager Admin permission.
    await appendVersion();
  } catch (error) {
    if ((error as {code?: number})?.code !== 5) throw error;
    // Initial setup: an administrator may create these three secrets once.
    // Afterwards the function can run with narrowly scoped access.
    try {
      await secretClient.createSecret({
        parent, secretId,
        secret: {replication: {automatic: {}}},
      });
    } catch (createError) {
      if ((createError as {code?: number})?.code !== 6) throw createError;
    }
    await appendVersion();
  }
}

/** Only an authenticated Level-4 admin may invoke this on the server. */
export async function configureTwilioCredentials(input: SmsCredentials): Promise<void> {
  if (!/^AC[0-9a-f]{32}$/i.test(input.accountSid) ||
      !/^[0-9a-f]{32}$/i.test(input.authToken) ||
      !/^\+[1-9][0-9]{7,14}$/.test(input.from)) {
    throw new HttpsError('invalid-argument', 'Check Twilio SID, Auth Token, and sender number.');
  }
  // Fail closed: do not store invalid credentials and later claim they work.
  let verification;
  try {
    verification = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(input.accountSid)}.json`,
      {
        headers: {
          Authorization: `Basic ${Buffer.from(`${input.accountSid}:${input.authToken}`).toString('base64')}`,
        },
        signal: AbortSignal.timeout(12000),
      },
    );
  } catch (_) {
    throw new HttpsError('unavailable', 'Twilio verification is temporarily unavailable.');
  }
  if (!verification.ok) {
    throw new HttpsError('failed-precondition', 'Twilio rejected the Account SID or Auth Token.');
  }
  try {
    await writeSecret(names.accountSid, input.accountSid);
    await writeSecret(names.authToken, input.authToken);
    await writeSecret(names.from, input.from);
  } catch (_) {
    // Never log credentials or provider responses.
    throw new HttpsError('failed-precondition',
      'The Firebase server needs Secret Manager permissions to save SMS settings.');
  }
}
