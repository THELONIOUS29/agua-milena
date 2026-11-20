// Firebase Messaging Service Worker para Agua Milena PWA
// Maneja notificaciones push en segundo plano (cuando la pestaña está cerrada)
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "CONFIGURAR_LOCALMENTE",
  authDomain: "agua-milena.firebaseapp.com",
  projectId: "agua-milena",
  storageBucket: "agua-milena.firebasestorage.app",
  messagingSenderId: "504410173979",
  appId: "1:504410173979:web:d826d0dd9aa1cf68e2febe",
  measurementId: "G-P31SKZG7JD"
});

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
