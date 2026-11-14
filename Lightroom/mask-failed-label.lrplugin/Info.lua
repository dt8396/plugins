--[[
SCRIPTMETA-BEGIN
Script-ID=blue.nanika.photo.lightroom.mask-failed-label
Name=マスク失敗ラベリング
Author=mizu（ @mizubeni142202 ）、ReCos開発室（ @mizu_alpha ）
Target-App=Lightroom
Version=1.0.3
Meta-URL=https://github.com/dt8396/plugins/tree/main/Lightroom
Description-BEGIN
マスクの失敗がある写真に、カラーラベルと評価を設定します。
Sets a color label and a rating on photos whose masks have failed.
Description-END
SCRIPTMETA-END
]]

return {
    LrSdkVersion = 16.0,
    LrSdkMinimumVersion = 12.0,

    LrToolkitIdentifier = 'blue.nanika.photo.lightroom.mask-failed-label',

    LrPluginName = 'マスク失敗ラベリング',
    LrPluginNameLocale = {
        en = 'Mask Failure Labeling',
        ja = 'マスク失敗ラベリング',
    },

    LrPluginInfoUrl = 'https://github.com/dt8396/plugins/blob/main/Lightroom/mask-failed-label.md',

    LrInitPlugin = 'CheckUpdate.lua',
    LrForceInitPlugin = true,

    LrLibraryMenuItems = {
        {
            title = 'マスク失敗の写真にラベルと評価を設定',
            file = 'MarkFailedMasks.lua',
        },
    },

    VERSION = { major = 1, minor = 0, revision = 3, build = 0 },
}
