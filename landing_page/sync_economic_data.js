const fs = require('fs');
const path = require('path');

const DART_FILE = path.join(__dirname, '../lib/config/economic_vision_data.dart');
const OUTPUT_FILE = path.join(__dirname, 'economic_data.js');

try {
  const dartCode = fs.readFileSync(DART_FILE, 'utf8');

  // Helper to extract a simple string constant
  function extractString(varName) {
    const regex = new RegExp(`static const String ${varName}\\s*=\\s*('[^]*?');`, 'm');
    const match = dartCode.match(regex);
    if (!match) return '';
    return match[1].replace(/['\n\r+]/g, '').replace(/\s{2,}/g, ' ').trim();
  }

  // Extract fiveYearBuildUp list
  function extractFiveYear() {
    const regex = /fiveYearBuildUp\s*=\s*\[([\s\S]*?)\];/;
    const match = dartCode.match(regex);
    if (!match) return [];
    const lines = match[1].split('\n').filter(l => l.includes('('));
    return lines.map(line => {
      const parts = line.match(/\('([^']+)',\s*(\d+),\s*([\d.]+)\)/);
      if (parts) {
        return { label: parts[1], amount: parseInt(parts[2]), barValue: parseFloat(parts[3]) };
      }
      return null;
    }).filter(Boolean);
  }

  function extractCorePoints() {
    const regex = /myAllin1CorePoints\s*=\s*\[([\s\S]*?)\];/;
    const match = dartCode.match(regex);
    if (!match) return [];
    
    const items = [];
    const tupleRegex = /\(\s*'([^']+)'\s*,([\s\S]*?),\s*Icons\.[^)]+\)/g;
    let m;
    while ((m = tupleRegex.exec(match[1])) !== null) {
       const title = m[1];
       const desc = m[2].replace(/['\n\r+]/g, '').replace(/\s{2,}/g, ' ').trim();
       items.push({title, desc});
    }
    return items;
  }

  function extractSolutionRows() {
    const regex = /solutionRows\s*=\s*\[([\s\S]*?)\];/;
    const match = dartCode.match(regex);
    if (!match) return [];
    
    const items = [];
    const tupleRegex = /\(Icons\.[^,]+,\s*'([^']+)'\s*,\s*'([^']+)'\)/g;
    let m;
    while ((m = tupleRegex.exec(match[1])) !== null) {
      items.push({ big: m[1], label: m[2] });
    }
    return items;
  }

  function extractIndustryFacts() {
    const regex = /industryFacts\s*=\s*\[([\s\S]*?)\];/;
    const match = dartCode.match(regex);
    if (!match) return [];
    
    const items = [];
    const tupleRegex = /\(\s*'([^']+)'\s*,\s*'([^']+)'\s*\)/g;
    let m;
    while ((m = tupleRegex.exec(match[1])) !== null) {
      items.push({ big: m[1], label: m[2] });
    }
    return items;
  }

  // Extract sectors list
  function extractSectors(listName) {
    const regex = new RegExp(`${listName}\\s*=\\s*\\[([\\s\\S]*?)\\];`);
    const match = dartCode.match(regex);
    if (!match) return [];
    
    const items = [];
    const blockRegex = /VisionSector\s*\([\s\S]*?\)/g;
    const blocks = match[1].match(blockRegex) || [];
    
    for (const block of blocks) {
      const labelMatch = block.match(/label:\s*'([^']+)'/);
      const amountMatch = block.match(/amount:\s*'([^']+)'/);
      const barMatch = block.match(/barValue:\s*([\d.]+)/);
      if (labelMatch && amountMatch && barMatch) {
        items.push({
          label: labelMatch[1],
          amount: amountMatch[1],
          barValue: parseFloat(barMatch[1])
        });
      }
    }
    return items;
  }

  const data = {
    heroAmount: extractString('heroAmount'),
    heroCaption: extractString('heroCaption'),
    heroRally: extractString('heroRally'),
    heroBadge: extractString('heroBadge'),
    annualRange: extractString('annualRange'),
    annualIntro: extractString('annualIntro'),
    fiveYearTotal: extractString('fiveYearTotal'),
    fiveYearBuildUp: extractFiveYear(),
    group1Title: extractString('group1Title'),
    group1Note: extractString('group1Note'),
    group2Title: extractString('group2Title'),
    group2Note: extractString('group2Note'),
    addressableSectors: extractSectors('addressableSectors'),
    importSectors: extractSectors('importSectors'),
    myAllin1CorePoints: extractCorePoints(),
    solutionTitle: extractString('solutionTitle'),
    solutionRows: extractSolutionRows(),
    solutionSlogan: extractString('solutionSlogan'),
    industryFacts: extractIndustryFacts(),
    ctaTitle: extractString('ctaTitle'),
    ctaBody: extractString('ctaBody'),
    ctaButton: extractString('ctaButton'),
    ctaButtonHero: extractString('ctaButtonHero'),
    sourceTitle: extractString('sourceTitle'),
    sourceBody: extractString('sourceBody'),
  };

  const outputContent = `// AUTO-GENERATED from lib/config/economic_vision_data.dart
// DO NOT EDIT DIRECTLY. Run 'node sync_economic_data.js' to update.

window.EconomicVisionData = ${JSON.stringify(data, null, 2)};
`;

  fs.writeFileSync(OUTPUT_FILE, outputContent);
  console.log('Successfully synced economic_vision_data.dart -> economic_data.js');
} catch (error) {
  console.error('Error syncing economic data:', error);
}
