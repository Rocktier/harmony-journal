/**
 * 应用元信息（单测可读 —— smoke test 靠它验证 esbuild 编译管线；
 * 将来「关于」页 / 导出文件头 / 备份格式版本号都从这里取，避免散落各处）
 */
export const APP_NAME_CN: string = 'Rock私记';
export const APP_NAME_EN: string = 'RockJournal';
export const APP_BUNDLE_NAME: string = 'com.rocktier.rockjournal';
/** 语义化版本，与 AppScope/app.json5 的 versionName 保持一致（改时两处一起改） */
export const APP_VERSION: string = '0.1.0';
/** 与 app.json5 的 versionCode 保持一致 */
export const APP_VERSION_CODE: number = 10000;
