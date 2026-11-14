-- 起動時に SCRIPTMETA の配布情報を読み、新しい版があれば知らせる

local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local HTTP_TIMEOUT_SECONDS = 15
local MAX_BODY_BYTES = 256 * 1024
local MAX_REDIRECTS = 8

local function trim(value)
    if value == nil then
        return ''
    end
    return tostring(value):match('^%s*(.-)%s*$') or ''
end

local function eachLine(text, visitor)
    local normalized = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    for line in string.gmatch(normalized .. '\n', '(.-)\n') do
        visitor(line)
    end
end

local function stripDescription(text)
    local kept = {}
    local skipping = false
    eachLine(text, function(line)
        local trimmed = trim(line)
        if trimmed == 'Description-BEGIN' then
            skipping = true
        elseif trimmed == 'Description-END' then
            skipping = false
        elseif not skipping then
            table.insert(kept, line)
        end
    end)
    return table.concat(kept, '\n')
end

local function parseKey(line)
    local trimmed = trim(line)
    if trimmed == '' then
        return nil, nil
    end
    local equals = trimmed:find('=', 1, true)
    if not equals then
        return nil, nil
    end
    return trim(trimmed:sub(1, equals - 1)), trim(trimmed:sub(equals + 1))
end

local function firstRegion(text, beginMarker, endMarker, searchFrom)
    local startAt = text:find(beginMarker, searchFrom or 1, true)
    if not startAt then
        return nil, nil
    end
    local contentStart = startAt + #beginMarker
    local endAt = text:find(endMarker, contentStart, true)
    if not endAt then
        return nil, nil
    end
    return text:sub(contentStart, endAt - 1), endAt + #endMarker
end

local function blockHasMetaUrl(block)
    local found = false
    eachLine(stripDescription(block), function(line)
        local key = parseKey(line)
        if key == 'Meta-URL' or key == 'META-URL' then
            found = true
        end
    end)
    return found
end

local function selectDistributionBlock(text)
    local distribution = firstRegion(text, 'SCRIPTMETA-DIST-BEGIN', 'SCRIPTMETA-DIST-END', 1)
    if distribution then
        return distribution
    end

    local searchFrom = 1
    while true do
        local block, nextFrom = firstRegion(text, 'SCRIPTMETA-BEGIN', 'SCRIPTMETA-END', searchFrom)
        if not block then
            return nil
        end
        if not blockHasMetaUrl(block) then
            return block
        end
        searchFrom = nextFrom
    end
end

local function findRecord(block, scriptId)
    local current = nil
    local matched = nil
    eachLine(stripDescription(block), function(line)
        local key, value = parseKey(line)
        if key == 'Script-ID' then
            current = { scriptId = value }
            if value == scriptId then
                matched = current
            end
        elseif current and key and current.scriptId == scriptId then
            current[key] = value
            matched = current
        end
    end)
    return matched
end

local function readLocalMetadata()
    local infoPath = LrPathUtils.child(_PLUGIN.path, 'Info.lua')
    local text = LrFileUtils.readFile(infoPath)
    if type(text) ~= 'string' then
        return nil
    end

    local block = firstRegion(text, 'SCRIPTMETA-BEGIN', 'SCRIPTMETA-END', 1)
    if not block then
        return nil
    end

    local fields = {}
    eachLine(stripDescription(block), function(line)
        local key, value = parseKey(line)
        if key then
            fields[key] = value
        end
    end)

    local scriptId = fields['Script-ID']
    local version = fields.Version
    local metaUrl = fields['Meta-URL'] or fields['META-URL']
    if scriptId == nil or scriptId == '' or version == nil or version == '' or metaUrl == nil or metaUrl == '' then
        return nil
    end

    return {
        scriptId = scriptId,
        version = version,
        metaUrl = metaUrl,
    }
end

local function normalizeVersion(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub('%s+', '')
    local startIndex = text:find('%d+')
    if not startIndex then
        return nil
    end

    local index = startIndex
    local length = #text
    while index <= length and text:sub(index, index):match('%d') do
        index = index + 1
    end
    while text:sub(index, index) == '.' and text:sub(index + 1, index + 1):match('%d') do
        index = index + 1
        while index <= length and text:sub(index, index):match('%d') do
            index = index + 1
        end
    end

    return text:sub(startIndex, index - 1)
end

local function versionParts(version)
    local parts = {}
    for part in string.gmatch(version, '%d+') do
        table.insert(parts, tonumber(part))
    end
    return parts
end

-- 解釈できない版は同じものとして扱い、通知しない
local function remoteIsNewer(localVersion, remoteVersion)
    local localNumeric = normalizeVersion(localVersion)
    local remoteNumeric = normalizeVersion(remoteVersion)
    if not localNumeric or not remoteNumeric then
        return false
    end

    local localParts = versionParts(localNumeric)
    local remoteParts = versionParts(remoteNumeric)
    local count = math.max(#localParts, #remoteParts)
    for index = 1, count do
        local localPart = localParts[index] or 0
        local remotePart = remoteParts[index] or 0
        if remotePart > localPart then
            return true
        end
        if remotePart < localPart then
            return false
        end
    end
    return false
end

local function normalizeUrl(value)
    local text = trim(value)
    if text == '' then
        return nil
    end
    local quote = text:sub(1, 1)
    if (quote == '"' or quote == "'") and text:sub(-1) == quote and #text >= 2 then
        text = text:sub(2, -2)
    end
    if text:match('^https?:/[^/]') then
        text = text:gsub('^(https?):/', '%1://', 1)
    end
    if not text:find('://', 1, true) then
        text = 'https://' .. text
    end
    local scheme, host = text:match('^(https?)://([^/%?#]+)')
    if not scheme or not host or host == '' then
        return nil
    end
    return text
end

local function canonicalUrl(url)
    local normalized = normalizeUrl(url)
    if not normalized then
        return nil
    end
    local scheme, host, path = normalized:match('^(https?)://([^/%?#]+)([^%?#]*)')
    if not scheme then
        return nil
    end
    path = path or ''
    if #path > 1 and path:sub(-1) == '/' then
        path = path:sub(1, -2)
    end
    return scheme:lower() .. '://' .. host:lower() .. path
end

local function pathComponents(path)
    local parts = {}
    for part in string.gmatch(path or '', '[^/]+') do
        table.insert(parts, part)
    end
    return parts
end

local function githubRawCandidates(url)
    local host, path = url:match('^https?://([^/%?#]+)([^%?#]*)')
    if not host or host:lower() ~= 'github.com' then
        return nil
    end

    local parts = pathComponents(path)
    if #parts == 2 then
        local owner = parts[1]
        local repo = parts[2]
        local prefix = 'https://raw.githubusercontent.com/' .. owner .. '/' .. repo .. '/'
        return {
            prefix .. 'HEAD/SCRIPTMETA.txt',
            prefix .. 'main/SCRIPTMETA.txt',
            prefix .. 'master/SCRIPTMETA.txt',
        }
    end

    if #parts >= 5 and parts[3] == 'tree' then
        local directory = {}
        local index = 5
        while index <= #parts do
            table.insert(directory, parts[index])
            index = index + 1
        end
        return {
            'https://raw.githubusercontent.com/'
                .. parts[1] .. '/'
                .. parts[2] .. '/'
                .. parts[4] .. '/'
                .. table.concat(directory, '/')
                .. '/SCRIPTMETA.txt',
        }
    end

    return nil
end

local function gistRawCandidates(url)
    local host, path = url:match('^https?://([^/%?#]+)([^%?#]*)')
    if not host or not host:lower():find('gist.github.com', 1, true) then
        return nil
    end

    local parts = pathComponents(path)
    if #parts < 2 then
        return nil
    end

    local user = parts[1]
    local gistId = parts[2]
    return {
        'https://gist.githubusercontent.com/' .. user .. '/' .. gistId .. '/raw/SCRIPTMETA.txt',
        'https://gist.githubusercontent.com/' .. user .. '/' .. gistId .. '/raw/scriptmeta.txt',
        'https://gist.github.com/' .. user .. '/' .. gistId .. '/raw/SCRIPTMETA.txt',
        'https://gist.github.com/' .. user .. '/' .. gistId .. '/raw/scriptmeta.txt',
    }
end

local function hasMetadataBlock(text)
    local hasDistribution = text:find('SCRIPTMETA-DIST-BEGIN', 1, true)
        and text:find('SCRIPTMETA-DIST-END', 1, true)
    if hasDistribution then
        return true
    end
    return text:find('SCRIPTMETA-BEGIN', 1, true) and text:find('SCRIPTMETA-END', 1, true)
end

local function httpGet(url)
    local body, headers = LrHttp.get(url, nil, HTTP_TIMEOUT_SECONDS)
    if type(headers) ~= 'table' or type(headers.status) ~= 'number' then
        return nil, false
    end
    if headers.status < 200 or headers.status > 299 then
        return nil, true
    end
    if type(body) ~= 'string' then
        return nil, true
    end
    if #body > MAX_BODY_BYTES then
        body = body:sub(1, MAX_BODY_BYTES)
    end
    return body, true
end

local function httpGetWithRetry(url)
    local body, completed = httpGet(url)
    if body or completed then
        return body
    end

    LrTasks.sleep(1)
    body, completed = httpGet(url)
    if body or completed then
        return body
    end

    LrTasks.sleep(3)
    body = httpGet(url)
    return body
end

local function loadDistributionText(pageUrl)
    local candidates = gistRawCandidates(pageUrl) or githubRawCandidates(pageUrl)
    if not candidates then
        return httpGetWithRetry(pageUrl)
    end

    for _, candidate in ipairs(candidates) do
        local body = httpGetWithRetry(candidate)
        if body and hasMetadataBlock(body) then
            return body
        end
    end
    return nil
end

local function recordVersion(record)
    if record.Version and record.Version ~= '' then
        return record.Version
    end
    if record['Latest-Version'] and record['Latest-Version'] ~= '' then
        return record['Latest-Version']
    end
    return nil
end

local function recordLatestUrl(record)
    local latest = record['Latest-URL']
    if latest == nil or latest == '' then
        latest = record['Latest-Page-URL']
    end
    if latest == nil or latest == '' then
        return nil
    end
    return normalizeUrl(latest)
end

local function resolveRemote(metadata)
    local currentUrl = normalizeUrl(metadata.metaUrl)
    if not currentUrl then
        return nil
    end

    local visited = {}
    visited[canonicalUrl(currentUrl)] = true
    local redirects = 0

    while true do
        local text = loadDistributionText(currentUrl)
        if not text then
            return nil
        end

        local block = selectDistributionBlock(text)
        if not block then
            return nil
        end

        local record = findRecord(block, metadata.scriptId)
        if not record then
            return nil
        end

        local latestUrl = recordLatestUrl(record)
        local latestKey = latestUrl and canonicalUrl(latestUrl) or nil
        local currentKey = canonicalUrl(currentUrl)
        local canFollow = latestKey
            and latestKey ~= currentKey
            and not visited[latestKey]
            and redirects < MAX_REDIRECTS

        if canFollow then
            redirects = redirects + 1
            visited[latestKey] = true
            currentUrl = latestUrl
        elseif latestKey and latestKey ~= currentKey then
            return nil
        else
            return {
                version = recordVersion(record),
                openUrl = currentUrl,
            }
        end
    end
end

local function notifyIfNewer(metadata, remote)
    if not remote or not remote.version then
        return
    end
    if not remoteIsNewer(metadata.version, remote.version) then
        return
    end

    -- 再表示しないを選んだあとに保存済みのボタンが返っても、ページは開かない
    local started = LrDate.currentTime()
    local verb = LrDialogs.promptForActionWithDoNotShow {
        message = 'マスク失敗ラベリングの新しい版があります。',
        info = string.format(
            'お使いの版は %s、配布されている版は %s です。',
            metadata.version,
            remote.version
        ),
        actionPrefKey = 'mask-failed-label-update-' .. remote.version,
        verbBtns = {
            { label = '配布サイトを開く', verb = 'open' },
        },
    }

    if verb == 'open' and (LrDate.currentTime() - started) >= 0.3 then
        LrHttp.openUrlInBrowser(remote.openUrl)
    end
end

local function runCheck()
    local metadata = readLocalMetadata()
    if not metadata then
        return
    end
    local remote = resolveRemote(metadata)
    notifyIfNewer(metadata, remote)
end

LrTasks.startAsyncTask(function()
    LrTasks.pcall(runCheck)
end)
