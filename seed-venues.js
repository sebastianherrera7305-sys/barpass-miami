const admin = require('firebase-admin');
const path = require('path');

// Cargar la clave de servicio (descargar de Firebase Console)
const serviceAccount = require('./service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Leer los venues del HTML
const fs = require('fs');
const html = fs.readFileSync(path.join(__dirname, 'barpass-miami.html'), 'utf8');
const match = html.match(/const VENUES = (\[[\s\S]*?\]);/);
if (!match) { console.log('No se encontraron venues'); process.exit(1); }

const venues = eval(match[1]);

async function upload() {
  const batch = db.batch();
  
  for (const v of venues) {
    const ref = db.collection('venues').doc(String(v.id));
    batch.set(ref, {
      ...v,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  
  await batch.commit();
  console.log(`✅ ${venues.length} venues subidos a Firestore`);
}

upload().catch(console.error);
