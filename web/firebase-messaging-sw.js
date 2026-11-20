// Firebase Messaging Service Worker para Agua Milena PWA
// Maneja notificaciones push en segundo plano (cuando la pestaña está cerrada)
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

try { importScripts('firebase-config.local.js'); } catch (_) {}
if (self.firebaseConfig && self.firebaseConfig.apiKey) {
  firebase.initializeApp(self.firebaseConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Agua Milena';
  const options = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };
  return self.registration.showNotification(title, options);
});

}
