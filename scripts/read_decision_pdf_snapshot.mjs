// Read-only production projection for PDF QA. Never writes to Firebase and never
// exports credentials, contact information, free-text notes or original names/IDs.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const project = process.env.FIREBASE_PROJECT_ID;
if (project !== 'nrc-aid') throw new Error('Unexpected production project');
const account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
if (!account.client_email || !account.private_key || account.project_id !== project) {
  throw new Error('Missing or mismatched protected service account');
}
const now = Math.floor(Date.now() / 1000);
const encode = x => Buffer.from(JSON.stringify(x)).toString('base64url');
const unsigned = encode({alg:'RS256',typ:'JWT'}) + '.' + encode({
  iss:account.client_email, scope:'https://www.googleapis.com/auth/datastore',
  aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+600,
});
const assertion = unsigned + '.' + crypto.sign('RSA-SHA256', Buffer.from(unsigned),
  account.private_key).toString('base64url');
const auth = await fetch('https://oauth2.googleapis.com/token', {
  method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},
  body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),
});
if (!auth.ok) throw new Error('Protected OAuth failed: '+auth.status);
const token = (await auth.json()).access_token;
if (!token) throw new Error('No access token');
const salt = crypto.randomBytes(32);
const pseudonym = x => x == null || x === '' ? '' :
  crypto.createHmac('sha256',salt).update(String(x)).digest('hex').slice(0,20);
const referenceFields = ['workerId','userId','groupId','groupNumber','group',
  'municipalityCoordinatorId','municipalityId','number','cycleId'];
const common = ['isActive','isDeleted','status','createdAt','updatedAt',
  ...referenceFields];
const columns = {
  operations:[...common,'_entity','name','groupName','job','type','isReserve',
    'shift','absenceReason','leaveType','startedAt','completedAt','weightTons','tons',
    'estimatedQuantity','quantity','quantityUnit','unit','tripPpe','ppe',
    'targetTons','dailyTargetTons','targetTrips','dailyTargetTrips','shiftCompletedAt'],
  users:[...common,'role'],
  trips:[...common,'startedAt','completedAt','weightTons','tons','estimatedQuantity',
    'quantity','quantityUnit','unit','tripPpe','ppe'],
  containers:[...common,'fullSince'],
  dumpsites:[...common,'capacity','fillPercentage'],
  work_cycles:[...common,'startDate','endDate'],
  cycles:[...common,'startDate','endDate'],
};
function decode(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields||{})
    .map(([k,x])=>[k,decode(x)]));
  if ('arrayValue' in v) return (v.arrayValue.values||[]).map(decode);
  return null;
}
const snapshot = {now:new Date().toISOString(),shiftText:'08:00 - 16:00',
  source:'production-read-only-sanitized',capped:[],counts:{},collections:{}};
for (const [collection,fields] of Object.entries(columns)) {
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`, {
    method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},
    body:JSON.stringify({structuredQuery:{from:[{collectionId:collection}],
      select:{fields:[...new Set(fields)].map(fieldPath=>({fieldPath}))},limit:5001}}),
  });
  if (!response.ok) throw new Error('Read-only snapshot failed for '+collection+': '+response.status);
  const documents = (await response.json()).filter(x=>x.document).map(x=>x.document);
  if (documents.length > 5000) snapshot.capped.push(collection);
  const rows = documents.slice(0,5000).map((doc,index)=>{
    const row = Object.fromEntries(Object.entries(doc.fields||{}).map(([k,v])=>[k,decode(v)]));
    row.id = pseudonym(doc.name.split('/').at(-1));
    // Keep group aliases consistent without exposing their original values.
    const alias = row.name || row.groupName;
    for (const field of referenceFields) if (row[field] != null) row[field]=pseudonym(row[field]);
    delete row.name; delete row.groupName;
    if (row._entity === 'group') {
      row.name='المجموعة '+(index+1);
      if (alias) row.groupName=pseudonym(alias);
    }
    if (collection === 'dumpsites') row.nameAr='المكب '+(index+1);
    if (collection === 'containers') row.locationName='الحاوية '+(index+1);
    // The analytics uses only enumerated job/type/status values, never descriptions.
    for (const field of ['job','type','status','absenceReason','leaveType']) {
      if (typeof row[field] === 'string' && row[field].length > 60) delete row[field];
    }
    return row;
  });
  snapshot.collections[collection]=rows;
  snapshot.counts[collection]=rows.length;
  console.log('Read-only sanitized projection: '+collection+' '+rows.length+
    (snapshot.capped.includes(collection)?' (capped)':''));
}
const output='build/decision-acceptance/snapshot.json';
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,JSON.stringify(snapshot),{mode:0o600});
console.log('No Firebase writes performed. Snapshot is temporary and is not uploaded.');
