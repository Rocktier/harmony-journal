/**
 * Rock私记 视觉 token —— 字阶 / 间距阶
 *
 * ⚠️ 为什么要有这个文件（2026-10-07 建立）：
 *   审计时发现全项目用了 **12 种字号**（9/10/11/12/13/14/15/16/17/18/20/22）与
 *   **106 处散落间距**（含 5/6/11/13/28 这类不在任何阶上的值）。后果是同类角色
 *   在不同页面长得不一样 —— 比如"页面标题"就有 18/20/22 三种，"次级文本"有 10/11/12 三种。
 *   那不是哪一个控件错了，而是**没有一把被共同遵守的尺子**。
 *
 * 规则：**所有字号只能取自 `RJ_FS_*`，所有间距只能取自 `RJ_SP_*`**。
 *   需要新值时先问"是不是现有档位够用"，实在不够才在这里加一档并写明用途。
 *
 * 单位说明：字号单位是 **fp**（ArkUI `.fontSize(数字)` 的默认单位），会随系统字体大小缩放；
 *   间距单位是 **vp**（布局尺寸，不随字号缩放）—— 两者不要混用。
 */

/** 字阶（fp）—— 7 档，按语义命名而非按大小命名 */
export const RJ_FS_DISPLAY: number = 22;  /** 解锁页主标题（唯一使用场景） */
export const RJ_FS_TITLE: number = 18;    /** 页面大标题：设置 / 隐私 / 首页 */
export const RJ_FS_BODY: number = 17;     /** 正文（编辑器与预览的唯一字号入口） */
export const RJ_FS_HEADING: number = 15;  /** 小节标题 */
export const RJ_FS_CALLOUT: number = 14;  /** 列表主行 / 设置项 */
export const RJ_FS_CAPTION: number = 12;  /** 按钮文字 / 次级说明 */
export const RJ_FS_META: number = 10;     /** 时间戳 / 统计 / 等宽数字 / 脚注 */

/** 间距阶（vp）—— 全是 4 的倍数 */
export const RJ_SP_XS: number = 2;    /** 极窄内边距（角标一类） */
export const RJ_SP_SM: number = 4;    /** 窄间距 */
export const RJ_SP_MD: number = 8;    /** 组件内默认间距 */
export const RJ_SP_LG: number = 12;   /** 相关内容之间的间距 */
export const RJ_SP_XL: number = 16;   /** 分组之间的间距 */
export const RJ_SP_XXL: number = 20;  /** 页面左右安全边距（本项目统一 20） */
export const RJ_SP_XXXL: number = 24; /** 大分区间距 */
