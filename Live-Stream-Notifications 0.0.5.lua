obs = obslua

local bot_token = ""
local chat_id = ""
local start_message = ""
local end_message = ""
local enable_start = true
local enable_end = true
local delete_start_message = false

local sent_message_ids = {}

function get_os()
    local os_name
    if package.config:sub(1,1) == "\\" then
        os_name = "Windows"
    else
        local handle = io.popen("uname -s")
        if handle then
            os_name = handle:read("*a"):gsub("%s+", "")
            handle:close()
        else
            os_name = "Unix"
        end
    end
    return os_name or "Unknown"
end

function json_escape(str)
    if not str then return "" end
    local escapes = {
        ['\\'] = '\\\\',
        ['"'] = '\\"',
        ['\b'] = '\\b',
        ['\f'] = '\\f',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t'
    }
    return str:gsub('[%c\\"]', escapes)
end

function send_telegram_message(message, message_type)
    if message == "" then return nil end
    if bot_token == "" or chat_id == "" then return nil end
    
    local os_type = get_os()
    local url = "https://api.telegram.org/bot" .. bot_token .. "/sendMessage"
    local message_id = nil
    
    local json_data = string.format('{"chat_id": "%s", "text": "%s", "parse_mode": "HTML"}', 
                                   chat_id, json_escape(message))
    
    local command
    if os_type == "Windows" then
        local temp_file = os.tmpname() .. ".json"
        local file = io.open(temp_file, "w")
        if file then
            file:write(json_data)
            file:close()
            command = string.format('curl -s -X POST -H "Content-Type: application/json" -d "@%s" "%s" && del "%s"', 
                                   temp_file, url, temp_file)
        else
            json_data = json_data:gsub('"', '\\"')
            command = string.format('curl -s -X POST -H "Content-Type: application/json" -d "%s" "%s"', 
                                   json_data, url)
        end
    else
        local temp_file = os.tmpname()
        local file = io.open(temp_file, "w")
        if file then
            file:write(json_data)
            file:close()
            command = string.format("curl -s -X POST -H 'Content-Type: application/json' -d '@%s' '%s' && rm -f '%s'", 
                                   temp_file, url, temp_file)
        else
            command = string.format("curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s'", 
                                   json_data, url)
        end
    end
    
    local handle = io.popen(command)
    if handle then
        local result = handle:read("*a")
        handle:close()
        
        if result and result:find('"ok":true') then
            local message_id_match = result:match('"message_id":(%d+)')
            if message_id_match then
                message_id = tonumber(message_id_match)
                if message_type == "start" then
                    sent_message_ids.start_message = message_id
                end
            end
        end
    end
    
    return message_id
end

function delete_telegram_message(message_id)
    if not message_id then return false end
    if bot_token == "" or chat_id == "" then return false end
    
    local os_type = get_os()
    local url = "https://api.telegram.org/bot" .. bot_token .. "/deleteMessage"
    local command
    local json_data = string.format('{"chat_id": "%s", "message_id": %d}', chat_id, message_id)
    
    if os_type == "Windows" then
        json_data = json_data:gsub('"', '\\"')
        command = string.format('curl -s -X POST -H "Content-Type: application/json" -d "%s" "%s"', 
                               json_data, url)
    else
        command = string.format("curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s'", 
                               json_data, url)
    end
    
    local handle = io.popen(command)
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result and result:find('"ok":true') or false
    end
    
    return false
end

function delete_start_stream_message()
    if sent_message_ids.start_message then
        local success = delete_telegram_message(sent_message_ids.start_message)
        if success then
            sent_message_ids.start_message = nil
        end
        return success
    end
    return false
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        if enable_start and start_message ~= "" then
            send_telegram_message(start_message, "start")
        end
    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        if delete_start_message then
            delete_start_stream_message()
        end
        if enable_end and end_message ~= "" then
            send_telegram_message(end_message, "end")
        end
    end
end

function test_start_stream_callback(props, p)
    if bot_token == "" or chat_id == "" then return false end
    local test_msg = start_message ~= "" and start_message or "Тест: Трансляция началась"
    send_telegram_message(test_msg, "start")
    return true
end

function test_end_stream_callback(props, p)
    if bot_token == "" or chat_id == "" then return false end
    local test_msg = end_message ~= "" and end_message or "Тест: Трансляция завершена"
    send_telegram_message(test_msg, "end")
    return true
end

function script_properties()
    local props = obs.obs_properties_create()
    
       -- Настройки отправки
    obs.obs_properties_add_text(props, "section1", "Настройка оповешений", obs.OBS_TEXT_INFO)
    
    local start_check = obs.obs_properties_add_bool(props, "enable_start", "Отправить при старте")
    obs.obs_property_set_long_description(start_check, "Включить отправку сообщения при начале трансляции")
    
    local delete_check = obs.obs_properties_add_bool(props, "delete_start_message", "Удалить при окончании стрима")
    obs.obs_property_set_long_description(delete_check, "Удалить сообщение о начале трансляции при ее окончании")
    
    local start_msg = obs.obs_properties_add_text(props, "start_message", "Сообщение при старте", obs.OBS_TEXT_MULTILINE)
    obs.obs_property_set_long_description(start_msg, "Текст сообщения, которое будет отправлено при начале трансляции")
    
    local end_check = obs.obs_properties_add_bool(props, "enable_end", "Отправить при окончании")
    obs.obs_property_set_long_description(end_check, "Включить отправку сообщения при окончании трансляции")
    
    local end_msg = obs.obs_properties_add_text(props, "end_message", "Сообщение при окончании", obs.OBS_TEXT_MULTILINE)
    obs.obs_property_set_long_description(end_msg, "Текст сообщения, которое будет отправлено при окончании трансляции")
    
    -- Раздел подключения
    obs.obs_properties_add_text(props, "section2", "Подключение", obs.OBS_TEXT_INFO)
    
    local token = obs.obs_properties_add_text(props, "bot_token", "Токен бота", obs.OBS_TEXT_PASSWORD)
    obs.obs_property_set_long_description(token, "Токен бота Telegram, полученный от @BotFather")
    
    local chat = obs.obs_properties_add_text(props, "chat_id", "ID чата", obs.OBS_TEXT_PASSWORD)
    obs.obs_property_set_long_description(chat, "ID чата или канала в Telegram (числовой идентификатор)")
    
    -- Раздел отладки
    obs.obs_properties_add_text(props, "section3", "Отладка", obs.OBS_TEXT_INFO)
    
    local test_start = obs.obs_properties_add_button(props, "test_start_button", "Тест: Старт", test_start_stream_callback)
    obs.obs_property_set_long_description(test_start, "Отправить тестовое сообщение о начале трансляции. Учитывает настройку удаления сообщения.")
    
    local test_end = obs.obs_properties_add_button(props, "test_end_button", "Тест: Конец", test_end_stream_callback)
    obs.obs_property_set_long_description(test_end, "Отправить тестовое сообщение об окончании трансляции")
    
 -- Инструкция
    local instructions = obs.obs_properties_add_text(props, "instructions", "Инструкция", obs.OBS_TEXT_INFO)
obs.obs_property_set_long_description(instructions, "ПОЛНАЯ ИНСТРУКЦИЯ НАСТРОЙКИ:\n\n" ..
" 1. СОЗДАНИЕ БОТА:\n" ..
"   • Найдите @BotFather в Telegram\n" ..
"   • Отправьте /newbot\n" ..
"   • Введите имя и username бота\n" ..
"   • Скопируйте токен (НИКОМУ НЕ ПЕРЕДАВАЙТЕ!)\n\n" ..
"2. ДОБАВЛЕНИЕ БОТА:\n" ..
"   • Личный чат: напишите боту /start\n" ..
"   • Группа: добавьте бота как участника\n" ..
"   • Канал: добавьте как администратора\n\n" ..
" 3. ПОЛУЧЕНИЕ ID ЧАТА:\n" ..
"   • Откройте web.telegram.org\n" ..
"   • Перейдите в нужный чат/канал\n" ..
"   • В адресной строке: .../#-123456789\n" ..
"   • Число после # - ваш chat_id\n" ..
"   • Или используйте @userinfobot\n\n" ..
"ПРИМЕРЫ ID:\n" ..
"   • Личный чат: 123456789\n" ..
"   • Группа/канал: -1001234567890\n\n" ..
" 4. НАСТРОЙКА В OBS:\n" ..
"   • Вставьте токен и chat_id\n" ..
"   • Настройте сообщения\n" ..
"   • Включите нужные опции\n" ..
"   • Протестируйте кнопками в разделе отладка\n\n" ..
"ВАЖНО:\n" ..
"   • Бот должен иметь права на отправку\n" ..
"   • Для каналов - права администратора\n" ..
"   • ID каналов всегда отрицательный\n" ..
"   • Сохраните настройки после ввода")
    


    return props
end

function script_description()
    return "Отправляет сообщения в Telegram при начале и окончании трансляции. Поддерживает удаление сообщения о начале при окончании стрима."
end

function script_load(settings)
    bot_token = obs.obs_data_get_string(settings, "bot_token")
    chat_id = obs.obs_data_get_string(settings, "chat_id")
    start_message = obs.obs_data_get_string(settings, "start_message")
    end_message = obs.obs_data_get_string(settings, "end_message")
    enable_start = obs.obs_data_get_bool(settings, "enable_start")
    enable_end = obs.obs_data_get_bool(settings, "enable_end")
    delete_start_message = obs.obs_data_get_bool(settings, "delete_start_message")
    
    sent_message_ids = {}
    obs.obs_frontend_add_event_callback(on_event)
end

function script_update(settings)
    bot_token = obs.obs_data_get_string(settings, "bot_token")
    chat_id = obs.obs_data_get_string(settings, "chat_id")
    start_message = obs.obs_data_get_string(settings, "start_message")
    end_message = obs.obs_data_get_string(settings, "end_message")
    enable_start = obs.obs_data_get_bool(settings, "enable_start")
    enable_end = obs.obs_data_get_bool(settings, "enable_end")
    delete_start_message = obs.obs_data_get_bool(settings, "delete_start_message")
end

function script_save(settings)
    obs.obs_data_set_string(settings, "bot_token", bot_token)
    obs.obs_data_set_string(settings, "chat_id", chat_id)
    obs.obs_data_set_string(settings, "start_message", start_message)
    obs.obs_data_set_string(settings, "end_message", end_message)
    obs.obs_data_set_bool(settings, "enable_start", enable_start)
    obs.obs_data_set_bool(settings, "enable_end", enable_end)
    obs.obs_data_set_bool(settings, "delete_start_message", delete_start_message)
end