const fs = require('fs');
const FILE = 'F:/HarmonyOs/car/entry/src/main/ets/services/recognition/RecognitionScheduler.ets';
const data = fs.readFileSync(FILE);
const text = data.toString('utf8');
const lines = text.split('\n');

// Check for mojibake: look for characters in CJK Compatibility ideographs / PUA range
// that appear in wrong contexts (mojibake chars are typically in U+E000-U+F8FF PUA
// or specific GBK-as-UTF8 code points like U+951B, U+6CB9, etc.)
console.log('=== Key runtime strings ===');
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("CANCELED, '") || lines[i].includes("TIMEOUT, '") ||
      lines[i].includes("e.message :")) {
    console.log(`L${i+1}: ${lines[i].trim()}`);
  }
}

// Find remaining non-ASCII lines
console.log('\n=== Lines with non-ASCII (excluding already-fixed) ===');
const goodChinese = '[\u4E00-\u9FFF]'; // Standard CJK Unified Ideographs
const mojibakeSuspect = /[\uE000-\uF8FF\u951B\u6CB9\u9524\u5822\u6564\u6D5C\u7F01\u71BB\u6D4E]/;

let count = 0;
for (let i = 0; i < lines.length; i++) {
  if (mojibakeSuspect.test(lines[i])) {
    console.log(`L${i+1}(idx=${i}): ${lines[i].substring(0, 100)}`);
    count++;
  }
}
console.log(`Total remaining: ${count}`);
