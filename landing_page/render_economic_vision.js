// Render the Economic Vision UI using window.EconomicVisionData

document.addEventListener('DOMContentLoaded', () => {
  if (!window.EconomicVisionData) return;
  const data = window.EconomicVisionData;

  const root = document.getElementById('economic-vision-root');
  
  function renderSector(sector) {
    const width = Math.max(5, sector.barValue * 100);
    return `
      <div class="ev-sector">
        <div class="ev-sector-header">
          <span class="ev-label">${sector.label}</span>
          <span class="ev-amount">${sector.amount}</span>
        </div>
        <div class="ev-bar-bg">
          <div class="ev-bar-fill" style="width: ${width}%"></div>
        </div>
      </div>
    `;
  }

  if (root) {
    const html = `
      <div class="ev-container">
        <div class="ev-hero-box">
          <div class="ev-badge">${data.heroBadge}</div>
          <h2 class="ev-hero-amount glow-number">${data.heroAmount}</h2>
          <p class="ev-hero-caption">${data.heroCaption}</p>
          <p class="ev-hero-rally">${data.heroRally}</p>
        </div>

        <div class="ev-annual-box">
          <h3>${data.annualRange}</h3>
          <p>${data.annualIntro}</p>
        </div>

        <div class="ev-group">
          <h3 class="ev-group-title">${data.group1Title}</h3>
          <p class="ev-group-note">${data.group1Note}</p>
          <div class="ev-sectors">
            ${data.addressableSectors.map(renderSector).join('')}
          </div>
        </div>

        <div class="ev-group" style="margin-top: 32px;">
          <h3 class="ev-group-title">${data.group2Title}</h3>
          <p class="ev-group-note">${data.group2Note}</p>
          <div class="ev-sectors">
            ${data.importSectors.map(renderSector).join('')}
          </div>
        </div>
        
        <div class="ev-total">
          <h3>${data.fiveYearTotal}</h3>
        </div>
      </div>
    `;
    root.innerHTML = html;
  }

  // --- NEW FULL REPORT SECTION ---
  const fullRoot = document.getElementById('economic-vision-full-container');
  if (fullRoot) {
    const renderYearRow = (y) => `
      <div style="display: flex; align-items: center; margin-bottom: 12px;">
        <div style="width: 60px; color: #8C7A88; font-size: 13px;">${y.label}</div>
        <div style="flex: 1; height: 10px; background: #FFEAF3; border-radius: 5px; margin: 0 12px; overflow: hidden;">
          <div style="height: 100%; background: #FF4FA3; border-radius: 5px; width: ${Math.max(5, y.barValue * 100)}%;"></div>
        </div>
        <div style="width: 80px; text-align: right; color: #201A22; font-size: 13px; font-weight: 700;">₹${y.amount} கோடி</div>
      </div>
    `;

    const renderSolutionRow = (r) => `
      <div style="display: flex; gap: 14px; margin-bottom: 16px; align-items: center;">
        <div style="background: rgba(255, 255, 255, 0.2); width: 44px; height: 44px; border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 20px; flex-shrink: 0; color: #fff;">💎</div>
        <div>
          <div style="font-size: 20px; font-weight: 900; color: #fff;">${r.big}</div>
          <div style="font-size: 13px; opacity: 0.92; color: #fff;">${r.label}</div>
        </div>
      </div>
    `;

    const renderFact = (f) => `
      <div style="display: flex; gap: 16px; margin-bottom: 16px; align-items: flex-start;">
        <div style="width: 70px; color: #BE2A7A; font-size: 18px; font-weight: 900; flex-shrink: 0;">${f.big}</div>
        <div style="color: #8C7A88; font-size: 14px; line-height: 1.5; padding-top: 2px;">${f.label}</div>
      </div>
    `;

    const fullHtml = `
      <!-- 5 Year Vision -->
      <div style="color: #201A22; font-size: 18px; font-weight: 800; margin-bottom: 12px;">📊 தமிழ்நாட்டின் 5 வருட சித்திரம்</div>
      <div style="background: #FFFFFF; border-radius: 18px; border: 1.5px solid #FFEAF3; padding: 16px; box-shadow: 0 8px 20px rgba(255, 79, 163, 0.07); margin-bottom: 24px;">
        <div style="color: #8C7A88; font-size: 14px; line-height: 1.5; margin-bottom: 10px;">${data.annualIntro}</div>
        <div style="display: flex; align-items: baseline;">
          <div style="color: #BE2A7A; font-size: 26px; font-weight: 900;">${data.annualRange}</div>
          <div style="color: #BE2A7A; font-size: 16px; font-weight: 800; margin-left: 6px;">கோடி</div>
        </div>
        <div style="color: #8C7A88; font-size: 14px;">கோடி வெளியேறுகிறது.</div>
        <div style="height: 1px; background: #FFEAF3; margin: 16px 0;"></div>
        <div style="color: #201A22; font-size: 14px; font-weight: 700; margin-bottom: 12px;">5 ஆண்டுகளில் (சந்தை வளர்ச்சியுடன்)</div>
        ${data.fiveYearBuildUp.map(renderYearRow).join('')}
        <div style="background: rgba(255, 79, 163, 0.1); border-radius: 12px; padding: 14px; text-align: center; margin-top: 12px;">
          <div style="color: #BE2A7A; font-size: 16px; font-weight: 900; line-height: 1.5;">நாம் முயற்சி செய்தால் மக்களிடமே சுமார் ∑ ${data.fiveYearTotal}</div>
        </div>
      </div>

      <!-- Solution Card -->
      <div style="color: #201A22; font-size: 18px; font-weight: 800; margin-bottom: 12px;">💡 MyAllin1 தீர்வு</div>
      <div style="background: linear-gradient(135deg, #00A84A, #007A33); border-radius: 18px; padding: 24px; box-shadow: 0 8px 20px rgba(0, 168, 74, 0.2); margin-bottom: 24px;">
        <div style="font-size: 18px; font-weight: 900; margin-bottom: 16px; color: #fff;">${data.solutionTitle}</div>
        ${data.solutionRows.map(renderSolutionRow).join('')}
        <div style="background: rgba(255, 255, 255, 0.16); padding: 14px; border-radius: 12px; text-align: center; font-size: 15px; font-weight: 800; margin-top: 20px; color: #fff;">${data.solutionSlogan}</div>
      </div>

      <!-- Industry Facts -->
      <div style="background: #FFFFFF; border-radius: 18px; border: 1.5px solid #FFEAF3; padding: 16px; box-shadow: 0 8px 20px rgba(255, 79, 163, 0.07); margin-bottom: 24px;">
        <div style="color: #201A22; font-size: 16px; font-weight: 800; margin-bottom: 16px;">📌 தொழில் துறை உண்மைகள்</div>
        ${data.industryFacts.map(renderFact).join('')}
      </div>

      <!-- CTA -->
      <div style="background: rgba(0, 168, 74, 0.1); border: 1px solid rgba(0, 168, 74, 0.4); border-radius: 18px; padding: 24px; text-align: center; margin-bottom: 24px;">
        <div style="font-size: 36px; margin-bottom: 12px;">❤️</div>
        <div style="color: #201A22; font-size: 16px; font-weight: 800; margin-bottom: 8px;">${data.ctaTitle}</div>
        <div style="color: #8C7A88; font-size: 14px; line-height: 1.5; margin-bottom: 20px;">${data.ctaBody}</div>
        <a href="https://my-allin1.web.app" target="_blank" style="display: block; width: 100%; background: #00A84A; color: #fff; padding: 16px; border-radius: 14px; font-size: 16px; font-weight: 800; text-decoration: none;">${data.ctaButton}</a>
      </div>

      <!-- Source Footer -->
      <div style="background: rgba(255, 234, 243, 0.6); padding: 16px; border-radius: 12px; margin-bottom: 40px;">
        <div style="color: #8C7A88; font-size: 13px; font-weight: 700; margin-bottom: 8px; display: flex; align-items: center; gap: 8px;">
          <span>📋</span> ${data.sourceTitle}
        </div>
        <div style="color: #8C7A88; font-size: 12px; line-height: 1.55;">${data.sourceBody}</div>
      </div>
    `;

    fullRoot.innerHTML = fullHtml;
  }
});
