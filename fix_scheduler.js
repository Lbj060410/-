// fix_scheduler.js - Fix all mojibake in RecognitionScheduler.ets
const fs = require('fs');
const FILE = 'F:/HarmonyOs/car/entry/src/main/ets/services/recognition/RecognitionScheduler.ets';

const data = fs.readFileSync(FILE);
let text = data.toString('utf8');
const lines = text.split('\n');

// Helper: replace a single line by index with new content
function replaceLine(idx, newContent) {
  // Preserve the original line ending (\r if present)
  const oldLine = lines[idx];
  const endsWithCr = oldLine.endsWith('\r');
  lines[idx] = newContent + (endsWithCr ? '\r' : '');
}

// Helper: replace a single line by index with multiple new lines
function replaceLineWithMultiple(idx, newLines) {
  const oldLine = lines[idx];
  const endsWithCr = oldLine.endsWith('\r');
  const joined = newLines.map((l, i) => l + (endsWithCr ? '\r' : '')).join('\n');
  lines[idx] = joined;
}

// ---- L41 (index 40): Combined Milestone 2 JSDoc line ----
// Content: " * Milestone 2锛...? * - LIVE锛..."
// Replace with two separate lines
replaceLineWithMultiple(40, [
  ' * Milestone 2：统一识别调度与任务队列',
  ' * - LIVE：忙则丢，不排队'
]);

// ---- L42 (index 41): SNAPSHOT JSDoc line ----
replaceLine(41, ' * - SNAPSHOT：排队执行，支持优先级、取消/超时');

// ---- L67 (index 66): stats comment ----
replaceLine(66, '  // ===== 统计（用于 Page4/Diagnostics）=====');

// ---- L75 (index 74): engine switch comment ----
replaceLine(74, '  // ===== 引擎动态切换 =====');

// ---- L115 (index 114): stop token comment ----
replaceLine(114, '    // ✅ 关键：切 token，杜绝 inFlight finally 后写 store');

// ---- L140 (index 139): backward compat comment ----
replaceLine(139, '  // 兼容旧接口：Milestone 1 的 RecognitionLoop.pushFrame');

// ---- L146 (index 145): JSDoc pushLiveFrame - combined line ----
// Content: "   * Page4 鎺ㄥ叆...? * - 蹇欏垯...? * - 鑻ユ湁..."
// Replace with three separate lines
replaceLineWithMultiple(145, [
  '   * Page4 推入实时帧',
  '   * - 忙则丢（不保留 pending、不排队）',
  '   * - 若有 snapshot/autoSnapshot 队列，LIVE 直接让路'
]);

// ---- L161 (index 160): rate control comment ----
replaceLine(160, '      // 频率控制：丢');

// ---- L176 (index 175): PAGE4_LIVE comment ----
replaceLine(175, '      source: RecognitionTaskSource.PAGE4_LIVE, // LIVE 来自 Page4 常流');

// ---- L191 (index 190): JSDoc enqueueLiveOnceFromPage2 - combined line ----
replaceLineWithMultiple(190, [
  '   * Page2：手动触发一次 LIVE 任务（支持 subtype）',
  '   * - 忙则丢（不排队）'
]);

// ---- L209 (index 208): SNAPSHOT queue comment ----
replaceLine(208, '    // SNAPSHOT 队列或引擎忙：LIVE 直接丢弃');

// ---- L226 (index 225): JSDoc enqueueSnapshotFromTap - combined line ----
replaceLineWithMultiple(225, [
  '   * Page4：点击 bbox 触发一次 Snapshot 高精识别（带 ROI）',
  '   * - 优先取 HTTP snapshot（更清晰）',
  '   * - HTTP 不可达时 fallback 用传入的 live pixelMap'
]);

// ---- L247 (index 246): JSDoc enqueueSnapshotFromPage2 - combined line ----
replaceLineWithMultiple(246, [
  '   * Page2：手动 Snapshot（最高优先级）',
  '   */'
]);

// ---- L266 (index 265): JSDoc enqueueAutoSnapshotTriggered line 1 ----
replaceLine(265, '   * 指令常驻触发：AutoSnapshot（中优先级）');

// ---- L267 (index 266): JSDoc enqueueAutoSnapshotTriggered line 2 ----
replaceLine(266, '   * - 当前项目尚未绑定到具体车端协议；保留统一入口即可');

// ---- L287 (index 286): JSDoc enqueueSnapshotFromGallery - combined line ----
replaceLineWithMultiple(286, [
  '   * 图库触发：把 PixelMap 直接作为输入（无需 HTTP）',
  '   */'
]);

// ---- L307 (index 306): queued comment ----
replaceLine(306, '    // queued：直接出队并标记取消');

// ---- L319 (index 318): RUNTIME STRING - cancel queue ----
replaceLine(318, "      this.store.updateRecogTaskState(taskId, RecognitionTaskState.CANCELED, '用户取消（队列）')");

// ---- L329 (index 328): internal enqueue comment ----
replaceLine(328, '  // ===== 内部：入队 =====');

// ---- L369 (index 368): busy flag comment ----
replaceLine(368, '    // busy 标识：Page4 overlay/面板显示');

// ---- L380 (index 379): late result comment ----
replaceLine(379, '      // stop() 后的 late result 不写 store');

// ---- L400 (index 399): SNAPSHOT comment ----
replaceLine(399, '        // SNAPSHOT：保存最近一次（Page4 下方截图预览也会被更新）');

// ---- L409 (index 408): report failure comment ----
replaceLine(408, '        // 回传失败不影响任务主流程');

// ---- L421 (index 420): RUNTIME STRING - cancelled ----
replaceLine(420, "        this.store.updateRecogTaskState(task.id, RecognitionTaskState.CANCELED, '取消')");

// ---- L424 (index 423): RUNTIME STRING - timeout ----
replaceLine(423, "        this.store.updateRecogTaskState(task.id, RecognitionTaskState.TIMEOUT, '超时')");

// ---- L427 (index 426): RUNTIME STRING - recognize failed ----
replaceLine(426, "        const msg: string = (e instanceof Error) ? e.message : '识别失败'");

// ---- L432 (index 431): cost comment ----
replaceLine(431, '      // 失败也要记 cost');

// ---- L643 (index 642): JSDoc cropPixelMapByRoi - combined line ----
replaceLineWithMultiple(642, [
  '   * 使用 PixelMap.crop 进行 ROI 裁剪（API12+）',
  '   * - 原地裁剪，会改变原 PixelMap',
  '   */'
]);

// ---- L669 (index 668): boundary comment ----
replaceLine(668, '    // 防止越界');

// Write the fixed file
const result = lines.join('\n');
fs.writeFileSync(FILE, result, 'utf8');
console.log('Done! Fixed all mojibake in RecognitionScheduler.ets');

// Verify a few key lines
const verifyLines = data.toString('utf8').split('\n');
const fixedLines = result.split('\n');
console.log('\nVerification of key runtime strings:');
[318, 420, 423, 426].forEach(i => {
  console.log(`L${i+1}: ${fixedLines[i]}`);
});
