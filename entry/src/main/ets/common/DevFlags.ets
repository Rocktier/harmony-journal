/**
 * 开发期开关（**提审前必须逐条关闭** —— 见 task_plan Phase 8 的待办）
 *
 * 党哥 2026-09-28 定：测试期间不要每次上锁解锁 → 预设密码 + 自动解锁。
 * 这不是设计缺陷，是**开发期快通道**：省掉每次启动输密码的成本，
 * 但代价是"任何拿到包的人都能进"，所以必须随提审一起关掉。
 */
/** true = 跳过解锁：启动时自动用 DEV_PASSWORD 建库/开库 */
export const DEV_UNLOCK_BYPASS: boolean = true;
/** 开发期预设密码（生产环境永远不会被使用：DEV_UNLOCK_BYPASS=false 时此值无效） */
export const DEV_PASSWORD: string = '19880211';
/** true = 界面上显示"开发模式"角标（防止忘记关掉就提审） */
export const DEV_SHOW_BADGE: boolean = true;
