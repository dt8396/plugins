--[[
SCRIPTMETA-BEGIN
Script-ID=blue.nanika.photo.lightroom.mask-failed-label
Name=マスク失敗ラベリング
Author=mizu
Target-App=Lightroom
Version=1.0.0
Meta-URL=https://github.com/dt8396/plugins/tree/main/Lightroom
Description-BEGIN
マスクの失敗がある写真に、カラーラベルと評価を設定します。
製作サークルは ReCos開発室（X @mizu_alpha）、製作者は mizu（X @mizubeni142202）です。
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

    LrPluginInfoUrl = 'https://photo.nanika.blue/plugins/',

    LrInitPlugin = 'CheckUpdate.lua',
    LrForceInitPlugin = true,

    LrLibraryMenuItems = {
        {
            title = 'マスク失敗の写真にラベルと評価を設定',
            file = 'MarkFailedMasks.lua',
        },
    },

    VERSION = { major = 1, minor = 0, revision = 0, build = 0 },
}
