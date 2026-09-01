/**
 * MYALLIN1 - PWA & APP INSTALLATION ENGINE
 * Handles Add-to-Home-Screen Prompts, Platform Detection, and Visual Install Guides.
 */

let deferredPrompt = null;

window.addEventListener('beforeinstallprompt', (e) => {
  // Prevent browser's default install banner
  e.preventDefault();
  deferredPrompt = e;

  // Show or highlight install buttons
  const pwaInstallButtons = document.querySelectorAll('.pwa-install-trigger');
  pwaInstallButtons.forEach(btn => {
    btn.style.display = 'inline-flex';
    btn.addEventListener('click', async () => {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        const { outcome } = await deferredPrompt.userChoice;
        if (outcome === 'accepted') {
          console.log('User accepted PWA installation');
        }
        deferredPrompt = null;
      } else {
        openPwaGuideModal();
      }
    });
  });
});

document.addEventListener('DOMContentLoaded', () => {
  initPwaGuideModal();
  initPlatformBadges();
});

/**
 * Platform Detection (Android vs iOS vs Desktop)
 */
function initPlatformBadges() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera;
  const isAndroid = /android/i.test(userAgent);
  const isIOS = /iPad|iPhone|iPod/.test(userAgent) && !window.MSStream;

  // Update install CTA hints
  const platformHints = document.querySelectorAll('.platform-hint');
  platformHints.forEach(hint => {
    if (isAndroid) {
      hint.textContent = 'Android போன்களில் உடனே வேலை செய்யும்';
    } else if (isIOS) {
      hint.textContent = 'iPhone Safari-ல் உடனே திறக்கும் (No App Store needed)';
    } else {
      hint.textContent = 'எந்த Browser-லும் உடனே திறக்கும்';
    }
  });
}

/**
 * PWA Visual "Add to Home Screen" Modal
 */
function initPwaGuideModal() {
  const guideTriggers = document.querySelectorAll('.open-pwa-guide');
  const guideModal = document.getElementById('pwaGuideModal');
  const guideCloseBtn = document.getElementById('pwaGuideClose');

  if (!guideModal) return;

  window.openPwaGuideModal = () => {
    guideModal.classList.add('active');
    document.body.style.overflow = 'hidden';
  };

  const closeModal = () => {
    guideModal.classList.remove('active');
    document.body.style.overflow = '';
  };

  guideTriggers.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      window.openPwaGuideModal();
    });
  });

  if (guideCloseBtn) guideCloseBtn.addEventListener('click', closeModal);

  guideModal.addEventListener('click', (e) => {
    if (e.target === guideModal) closeModal();
  });
}
