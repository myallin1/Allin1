/**
 * MYALLIN1 - CONVERSION RATE OPTIMIZATION (CRO) ENGINE
 * Powers Interactive Phone Simulator (with all app screenshot features),
 * Flash Deal Countdown, Savings Calculator, Live Social Proof, and QR Handover.
 */

document.addEventListener('DOMContentLoaded', () => {
  initPhoneSimulator();
  initFlashDealTimer();
  initSavingsCalculator();
  initSocialProofToast();
  initQrModal();
});

/**
 * 1. Interactive Phone Simulator
 */
function initPhoneSimulator() {
  const tabButtons = document.querySelectorAll('.mockup-tab-btn');
  const views = document.querySelectorAll('.mockup-view');
  const actionBtnText = document.getElementById('mockupActionText');

  const tabActionLabels = {
    'hero': 'Hire a Hero (உடனடி உதவி)',
    'ride': 'இப்போதே ரைடு புக் செய் (Web App)',
    'food': 'உணவு ஆர்டர் செய் (Food Genie)',
    'grocery': 'மளிகை ஆர்டர் செய் (Fresh Delivery)',
    'mobiles': 'Mobiles & Electronics Store',
    'eseva': 'E-Seva சேவைக்கு விண்ணப்பி',
    'chitti': 'Chitti Voice AI-யிடம் பேசு'
  };

  function switchTab(serviceKey) {
    // Update tab button states
    tabButtons.forEach(btn => {
      if (btn.dataset.tab === serviceKey) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    // Update views inside phone screen
    views.forEach(view => {
      if (view.id === `view-${serviceKey}`) {
        view.classList.add('active');
      } else {
        view.classList.remove('active');
      }
    });

    // Update bottom action label
    if (actionBtnText && tabActionLabels[serviceKey]) {
      actionBtnText.textContent = tabActionLabels[serviceKey];
    }
  }

  // Bind clicks on simulator tabs
  tabButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const tabKey = btn.dataset.tab;
      switchTab(tabKey);
    });
  });
}

/**
 * 2. Flash Deal Live Countdown Timer (Ref: Image 4 Marketly)
 */
function initFlashDealTimer() {
  const daysEl = document.getElementById('dealDays');
  const hrsEl = document.getElementById('dealHours');
  const minsEl = document.getElementById('dealMins');
  const secsEl = document.getElementById('dealSecs');

  if (!daysEl || !hrsEl || !minsEl || !secsEl) return;

  // Set target deal expiration date (3 days from now)
  let totalSeconds = 2 * 86400 + 14 * 3600 + 35 * 60 + 40;

  function updateTimer() {
    if (totalSeconds <= 0) {
      totalSeconds = 86400 * 3; // reset loop
    }

    const d = Math.floor(totalSeconds / 86400);
    const h = Math.floor((totalSeconds % 86400) / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;

    daysEl.textContent = String(d).padStart(2, '0');
    hrsEl.textContent = String(h).padStart(2, '0');
    minsEl.textContent = String(m).padStart(2, '0');
    secsEl.textContent = String(s).padStart(2, '0');

    totalSeconds--;
  }

  updateTimer();
  setInterval(updateTimer, 1000);
}

/**
 * 3. Interactive Local Savings Calculator
 */
function initSavingsCalculator() {
  const ridesInput = document.getElementById('calcRidesInput');
  const foodInput = document.getElementById('calcFoodInput');
  const ridesDisplay = document.getElementById('calcRidesVal');
  const foodDisplay = document.getElementById('calcFoodVal');
  const savingsAmountDisplay = document.getElementById('calcSavingsAmount');
  const savingsAnnualDisplay = document.getElementById('calcSavingsAnnual');

  if (!ridesInput || !foodInput || !savingsAmountDisplay) return;

  function calculateSavings() {
    const weeklyRides = parseInt(ridesInput.value, 10) || 0;
    const weeklyFood = parseInt(foodInput.value, 10) || 0;

    // National app surge / platform / driver commission penalty = ~₹35 per ride extra
    // National app restaurant markup (25-30%) + high delivery fee = ~₹75 per order extra
    const weeklyRideSavings = weeklyRides * 35;
    const weeklyFoodSavings = weeklyFood * 75;
    const weeklyTotal = weeklyRideSavings + weeklyFoodSavings;

    const monthlyTotal = weeklyTotal * 4.3;
    const annualTotal = monthlyTotal * 12;

    // Display formatted numbers
    ridesDisplay.textContent = `${weeklyRides} ரைட்ஸ்`;
    foodDisplay.textContent = `${weeklyFood} ஆர்டர்ஸ்`;

    savingsAmountDisplay.textContent = `₹${Math.round(monthlyTotal).toLocaleString('en-IN')}`;
    if (savingsAnnualDisplay) {
      savingsAnnualDisplay.textContent = `வருடத்திற்கு ₹${Math.round(annualTotal).toLocaleString('en-IN')} வரை உங்கள் சேமிப்பு!`;
    }
  }

  ridesInput.addEventListener('input', calculateSavings);
  foodInput.addEventListener('input', calculateSavings);

  calculateSavings();
}

/**
 * 4. Real-time Local Activity & Social Proof Toasts
 */
function initSocialProofToast() {
  const toastContainer = document.getElementById('liveToastContainer');
  if (!toastContainer) return;

  const activities = [
    {
      icon: '🛵',
      title: 'கார்த்திக் (Perundurai Road)',
      meta: 'பைக் டாக்சி புக் செய்தார் • 2 நிமிடம் முன்'
    },
    {
      icon: '🍛',
      title: 'பிரியா (Brough Road)',
      meta: 'பிரியாணி &amp; உணவு ஆர்டர் • 3 நிமிடம் முன்'
    },
    {
      icon: '🛒',
      title: 'செந்தில் (Thindal)',
      meta: 'Erode Fresh மளிகை டெலிவரி • 5 நிமிடம் முன்'
    },
    {
      icon: '📱',
      title: 'கௌதம் (PS Park)',
      meta: 'Mobiles &amp; Screen Repair புக் செய்தார் • 8 நிமிடம் முன்'
    },
    {
      icon: '🏍️',
      title: 'முத்து (Veerappanchatram)',
      meta: 'Hero Driver-ஆக இணைந்தார் (0% Commission) • 11 நிமிடம் முன்'
    },
    {
      icon: '📜',
      title: 'செல்வி (Solar)',
      meta: 'E-Seva Online சான்றிதழ் உதவி • 14 நிமிடம் முன்'
    }
  ];

  let currentIndex = 0;

  function showNextToast() {
    const item = activities[currentIndex];
    currentIndex = (currentIndex + 1) % activities.length;

    toastContainer.innerHTML = `
      <div class="live-toast show" role="status" aria-live="polite">
        <div class="toast-icon">${item.icon}</div>
        <div class="toast-content">
          <span class="toast-title">${item.title}</span>
          <span class="toast-meta">${item.meta}</span>
        </div>
      </div>
    `;

    setTimeout(() => {
      const toast = toastContainer.querySelector('.live-toast');
      if (toast) {
        toast.classList.remove('show');
      }
    }, 5000);
  }

  setTimeout(() => {
    showNextToast();
    setInterval(showNextToast, 11000);
  }, 4000);
}

/**
 * 5. Desktop-to-Mobile QR Code Modal
 */
function initQrModal() {
  const qrTriggers = document.querySelectorAll('.open-qr-modal');
  const qrModal = document.getElementById('qrModal');
  const qrCloseBtn = document.getElementById('qrModalClose');

  if (!qrModal) return;

  const openModal = (e) => {
    if (e) e.preventDefault();
    qrModal.classList.add('active');
    document.body.style.overflow = 'hidden';
  };

  const closeModal = () => {
    qrModal.classList.remove('active');
    document.body.style.overflow = '';
  };

  qrTriggers.forEach(trigger => trigger.addEventListener('click', openModal));
  if (qrCloseBtn) qrCloseBtn.addEventListener('click', closeModal);

  qrModal.addEventListener('click', (e) => {
    if (e.target === qrModal) closeModal();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && qrModal.classList.contains('active')) {
      closeModal();
    }
  });
}
