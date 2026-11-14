-- マスクの失敗がある写真へ、カラーラベルと評価を設定する

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local PLUGINS_URL = 'https://photo.nanika.blue/plugins/'

local COLOR_ITEMS = {
    { title = '変更しない', value = 'unchanged' },
    { title = '赤', value = 'red' },
    { title = '黄', value = 'yellow' },
    { title = '緑', value = 'green' },
    { title = '青', value = 'blue' },
    { title = '紫', value = 'purple' },
    { title = 'なし', value = 'none' },
}

local RATING_ITEMS = {
    { title = '変更しない', value = 'unchanged' },
    { title = 'なし', value = 'none' },
    { title = '星 1', value = '1' },
    { title = '星 2', value = '2' },
    { title = '星 3', value = '3' },
    { title = '星 4', value = '4' },
    { title = '星 5', value = '5' },
}

local function thresholdFromProperty(value)
    local threshold = tonumber(value)
    if threshold == nil or threshold < 1 or threshold > 9999 or threshold ~= math.floor(threshold) then
        return nil
    end
    return threshold
end

local function showChoiceDialog()
    return LrFunctionContext.callWithContext('mask-failed-label-dialog', function(context)
        local f = LrView.osFactory()
        local props = LrBinding.makePropertyTable(context)
        props.color = 'red'
        props.rating = 'unchanged'
        props.threshold = 1

        local contents = f:column {
            bind_to_object = props,
            spacing = f:control_spacing(),
            f:static_text {
                title = '失敗の判定には、SDK の実験的な現像設定を使います。Lightroom の更新で判定が変わることがあります。選択した写真を確認します。選択が無いときは、フィルムストリップの写真を確認します。',
                width_in_chars = 46,
                height_in_lines = 4,
            },
            f:static_text {
                title = '失敗しているマスクが、指定した件数以上の写真に設定します。',
                width_in_chars = 46,
                height_in_lines = 2,
            },
            f:row {
                spacing = f:label_spacing(),
                f:static_text {
                    title = '失敗マスク数',
                    width_in_chars = 14,
                },
                f:edit_field {
                    value = LrView.bind('threshold'),
                    min = 1,
                    max = 9999,
                    precision = 0,
                    width_in_digits = 4,
                    immediate = true,
                },
            },
            f:row {
                spacing = f:label_spacing(),
                f:static_text {
                    title = 'カラーラベル',
                    width_in_chars = 14,
                },
                f:popup_menu {
                    value = LrView.bind('color'),
                    items = COLOR_ITEMS,
                    width_in_chars = 16,
                },
            },
            f:row {
                spacing = f:label_spacing(),
                f:static_text {
                    title = '評価',
                    width_in_chars = 14,
                },
                f:popup_menu {
                    value = LrView.bind('rating'),
                    items = RATING_ITEMS,
                    width_in_chars = 16,
                },
            },
            f:row {
                spacing = f:label_spacing(),
                f:static_text {
                    title = 'Copyright (c) 2026 mizu, ReCos開発室',
                    font = '<system/small>',
                },
                f:static_text {
                    title = PLUGINS_URL,
                    font = '<system/small>',
                    text_color = LrColor(0, 0.3, 0.8),
                    mouse_down = function()
                        LrHttp.openUrlInBrowser(PLUGINS_URL)
                    end,
                },
            },
        }

        while true do
            local button = LrDialogs.presentModalDialog {
                title = 'マスク失敗ラベリング',
                contents = contents,
                actionVerb = '設定',
                cancelVerb = 'キャンセル',
            }

            if button ~= 'ok' then
                return nil
            end

            local threshold = thresholdFromProperty(props.threshold)
            if threshold ~= nil then
                return {
                    color = props.color,
                    rating = props.rating,
                    threshold = threshold,
                }
            end

            LrDialogs.message(
                'マスク失敗ラベリング',
                '失敗マスク数は、1以上9999以下の整数にしてください。'
            )
        end
    end)
end

local function countFailedMasks(photo)
    local ok, settings = LrTasks.pcall(function()
        return photo:getDevelopSettings()
    end)
    if not ok then
        return nil
    end
    if type(settings) ~= 'table' then
        return 0
    end

    local groups = settings.MaskGroupBasedCorrections
    if type(groups) ~= 'table' then
        return 0
    end

    local count = 0
    for _, group in pairs(groups) do
        if type(group) == 'table' then
            local masks = group.CorrectionMasks
            if type(masks) == 'table' then
                for _, mask in pairs(masks) do
                    if type(mask) == 'table'
                        and mask.What == 'Mask/Image'
                        and mask.ErrorReason ~= nil
                        and tostring(mask.ErrorReason) ~= '0' then
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

local function changeTargetName(colorChoice, ratingChoice)
    local changesColor = colorChoice ~= 'unchanged'
    local changesRating = ratingChoice ~= 'unchanged'
    if changesColor and changesRating then
        return 'カラーラベルと評価'
    end
    if changesColor then
        return 'カラーラベル'
    end
    return '評価'
end

local function skippedSentence(skipped)
    if skipped < 1 then
        return ''
    end
    return string.format(
        'このうち%d枚は現像設定を取得できなかったため、確認していません。',
        skipped
    )
end

local function resultMessage(total, applied, skipped, threshold, colorChoice, ratingChoice)
    local text
    if applied == 0 then
        text = string.format(
            '%d枚を確認しました。失敗しているマスクが%d件以上の写真はありませんでした。',
            total,
            threshold
        )
    else
        text = string.format(
            '%d枚を確認し、失敗しているマスクが%d件以上の%d枚に%sを設定しました。',
            total,
            threshold,
            applied,
            changeTargetName(colorChoice, ratingChoice)
        )
    end
    return text .. skippedSentence(skipped)
end

local function applyMetadata(catalog, photos, colorChoice, ratingChoice)
    local colorName = nil
    if colorChoice ~= 'unchanged' then
        colorName = colorChoice
    end

    local ratingSpecified = ratingChoice ~= 'unchanged'
    local ratingValue = nil
    if ratingSpecified and ratingChoice ~= 'none' then
        ratingValue = tonumber(ratingChoice)
    end

    catalog:withWriteAccessDo('マスク失敗の写真にラベルと評価を設定', function()
        for _, photo in ipairs(photos) do
            if colorName ~= nil then
                photo:setRawMetadata('colorNameForLabel', colorName)
            end
            if ratingSpecified then
                photo:setRawMetadata('rating', ratingValue)
            end
        end
    end)
end

local function scanPhotos(context, photos, threshold)
    local progress = LrDialogs.showModalProgressDialog {
        title = 'マスク失敗の写真にラベルと評価を設定',
        caption = string.format('0 / %d を確認しています', #photos),
        functionContext = context,
    }

    local failed = {}
    local skipped = 0
    local canceled = false

    for index, photo in ipairs(photos) do
        if progress:isCanceled() then
            canceled = true
            break
        end

        progress:setCaption(string.format('%d / %d を確認しています', index, #photos))
        progress:setPortionComplete(index - 1, #photos)

        local failedCount = countFailedMasks(photo)
        if failedCount == nil then
            skipped = skipped + 1
        elseif failedCount >= threshold then
            table.insert(failed, photo)
        end
    end

    progress:setPortionComplete(#photos, #photos)
    progress:done()

    return failed, skipped, canceled
end

local function main()
    local choice = showChoiceDialog()
    if not choice then
        return
    end

    if choice.color == 'unchanged' and choice.rating == 'unchanged' then
        LrDialogs.message(
            'マスク失敗ラベリング',
            'カラーラベルと評価はどちらも変更しないため、写真は変更しませんでした。'
        )
        return
    end

    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos() or {}
    if #photos == 0 then
        LrDialogs.message('マスク失敗ラベリング', '対象の写真がありません。')
        return
    end

    local outcome = LrFunctionContext.callWithContext('mask-failed-label-scan', function(context)
        local failedPhotos, skippedCount, wasCanceled = scanPhotos(context, photos, choice.threshold)
        return {
            failed = failedPhotos,
            skipped = skippedCount,
            canceled = wasCanceled,
        }
    end)
    local failed = outcome.failed
    local skipped = outcome.skipped
    local canceled = outcome.canceled

    if canceled then
        LrDialogs.message(
            'マスク失敗ラベリング',
            '確認を中止しました。ラベルと評価は変更していません。'
        )
        return
    end

    if #failed > 0 and #photos >= 2 then
        local info = string.format(
            '%d枚を確認し、失敗しているマスクが%d件以上の写真は%d枚でした。この%d枚に%sを設定しますか。',
            #photos,
            choice.threshold,
            #failed,
            #failed,
            changeTargetName(choice.color, choice.rating)
        ) .. skippedSentence(skipped)
        local answer = LrDialogs.confirm('マスク失敗ラベリング', info, '設定', 'キャンセル')
        if answer ~= 'ok' then
            LrDialogs.message(
                'マスク失敗ラベリング',
                string.format(
                    '%d枚を確認し、失敗しているマスクが%d件以上の写真は%d枚でした。設定をキャンセルしたため、ラベルと評価は変更していません。',
                    #photos,
                    choice.threshold,
                    #failed
                ) .. skippedSentence(skipped)
            )
            return
        end
    end

    if #failed > 0 then
        applyMetadata(catalog, failed, choice.color, choice.rating)
    end

    LrDialogs.message(
        'マスク失敗ラベリング',
        resultMessage(#photos, #failed, skipped, choice.threshold, choice.color, choice.rating)
    )
end

LrTasks.startAsyncTask(function()
    local ok, errorMessage = LrTasks.pcall(main)
    if not ok then
        LrDialogs.message(
            'マスク失敗ラベリング',
            '処理中にエラーが発生しました。\n' .. tostring(errorMessage),
            'critical'
        )
    end
end)
