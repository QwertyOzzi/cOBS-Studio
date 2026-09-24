--[[
  ============================================================
  cOBS — управление OBS Studio из GTA SA / SA-MP
  (MoonLoader, настроено под AriZona RP)

  Что умеет:
    * Подключение к OBS через встроенный WebSocket (OBS 28+),
      с авторизацией по паролю (SHA-256, как требует OBS 30+;
      пароль задаётся в настройках OBS: Сервис -> Настройки
      сервера WebSocket).
    * /co — окно настроек (кастомизация HUD, подсветка, уведомления).
    * Dynamic Island HUD в стиле iPhone: снизу по центру экрана,
      поверх твоей картинки-подложки показывается состояние OBS
      и записи (запись / стрим / повтор / камера + таймер).
    * При открытом чате HUD плавно «разворачивается»: появляется
      кнопка НАЧАТЬ/СТОП ЗАПИСЬ и детали записи (таймер, LIVE).
    * Амбиент-подсветка вокруг острова (вкл / всегда / авто-ночь,
      цвет и яркость настраиваются в /co).
    * Чёткие шрифты (TTF, рисуются без растяжения — без пикселей).
    * Уведомления вместо флуда в чат: всплывающие попапы
      (как Dynamic Island), режим выбирается в /co.
    * Кнопки в меню и горячие клавиши:
        F6  — запись вкл/выкл
        F7  — буфер повтора вкл/выкл
        F8  — сохранить повтор (как ShadowPlay)
        F9  — стрим вкл/выкл
        F10 — виртуальная камера вкл/выкл
        F11 — показать/скрыть меню
        /co — то же, что F11 (чат-команда)

  Картинка подложки:
    ...\moonloader\resource\cobs\Rectangle 1.png  (126x36)

  Настройки хранятся в ...\moonloader\config\cobs.ini

  Требования:
    * MoonLoader (ffi/bit/vkeys — встроены)
    * OBS Studio 28+ с включённым WebSocket-сервером
    * SAMPFUNCS — для чат-команды /co (не обязателен, меню можно
      открыть клавишей F11)

  Как запустить:
    1. Скопируй cOBS.lua в ...\moonloader\
    2. В OBS включи WebSocket-сервер и ЗАДАЙ пароль
    3. В игре: /co -> впиши хост/порт/пароль -> «Подключиться»
  ============================================================
]]

script_name("cOBS Studio")
script_author("Jimi_Hopper")
script_version("2.5")
script_description("cOBS Studio - Управление OBS Studio прямо из игры (by Jimi_Hopper)")

----------------------------------------------------------------
-- Авторские права и система контроля целостности (Anti-Tamper)
----------------------------------------------------------------
local AUTHOR_NAME = "Jimi_Hopper"
local AUTHOR_TG   = "https://t.me/+f6H5n_JAHOZhNTY6"
local AUTHOR_SEAL = "48d9651e7a0c3945e23c674ff7265abd983502422c4725cbd56e03f1ebbd0b5d"
local DEBUG_MODE  = false

require "moonloader"

local bit = require("bit")
local ffi = require("ffi")
local vkeys = require("vkeys")
local encoding = require("encoding")
encoding.default = "cp1251" -- для вывода в чат SAMP
local u8 = encoding.UTF8
local inicfg = require("inicfg")
local memory = require("memory")
ffi.cdef[[ unsigned int GetTickCount(void); ]]
local k32 = ffi.load("kernel32")

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

----------------------------------------------------------------
-- Настройки (по умолчанию; реальные хранятся в config\cobs.ini)
----------------------------------------------------------------
local CONFIG_PATH = "config\\cobs.ini"
local IMAGE_DIR   = "resource\\cobs"

local DEFAULTS = {
    audio = {
        mic_name = "",
        desktop_name = "",
    },
    main = {
        host       = "127.0.0.1",
        port       = 4455,
        password   = "",
        autoconnect = false,
    },
    hud = {
        enabled     = true,
        width       = 130,   -- ширина «острова» в пикселях (50..250)
        margin      = 28,    -- отступ от края экрана
        opacity     = 1.0,   -- прозрачность подложки и текста (0.25..1)
        show_sub    = true,  -- показывать вторую (маленькую) строку
        expanded    = true,  -- разворачивать «остров» при открытом чате
        pos_preset  = 0,     -- 0=снизу центр, 1=сверху центр, 2=сверху слева, 3=сверху справа, 4=снизу слева, 5=снизу справа, 6=кастом
        custom_x    = 0.5,   -- 0.0..1.0
        custom_y    = 0.9,   -- 0.0..1.0
    },
    glow = {
        mode      = 1,  -- 0 выкл, 1 всегда, 2 авто (ночь по игровому времени)
        intensity = 0.55,
        radius    = 1.6, -- размер свечения относительно высоты острова
        r         = 0.35,
        g         = 0.65,
        b         = 1.00,
    },
    notify = {
        mode     = 1,  -- 0 только в чат, 1 только UI уведомления, 2 и то и то
        duration = 3.0,-- сколько секунд показывать UI уведомление
    },
    hotkeys = {
        record_key   = 117, -- VK_F6
        record_alt   = false,
        record_ctrl  = false,
        record_shift = false,
        mic_key      = 116, -- VK_F5
        mic_alt      = false,
        mic_ctrl     = false,
        mic_shift    = false,
        replay_key   = 118, -- VK_F7
        replay_alt   = false,
        replay_ctrl  = false,
        replay_shift = false,
        save_key     = 119, -- VK_F8
        save_alt     = false,
        save_ctrl    = false,
        save_shift   = false,
        stream_key   = 120, -- VK_F9
        stream_alt   = false,
        stream_ctrl  = false,
        stream_shift = false,
        vcam_key     = 121, -- VK_F10
        vcam_alt     = false,
        vcam_ctrl    = false,
        vcam_shift   = false,
        menu_key     = 122, -- VK_F11
        menu_alt     = false,
        menu_ctrl    = false,
        menu_shift   = false,
    },
}

local cfg = inicfg.load(DEFAULTS, CONFIG_PATH)
cfg.audio = cfg.audio or {}
cfg.audio.mic_name = tostring(cfg.audio.mic_name or "")
cfg.audio.desktop_name = tostring(cfg.audio.desktop_name or "")
cfg.main.host = tostring(cfg.main.host or "127.0.0.1")
cfg.main.port = tonumber(cfg.main.port) or 4455
cfg.main.password = tostring(cfg.main.password or "")
cfg.main.autoconnect = cfg.main.autoconnect == true or false
cfg.hud.enabled = cfg.hud.enabled == true or false
cfg.hud.width = clamp(tonumber(cfg.hud.width) or 130, 50, 250)
cfg.hud.margin = tonumber(cfg.hud.margin) or 28
cfg.hud.opacity = tonumber(cfg.hud.opacity) or 1.0
cfg.hud.show_sub = cfg.hud.show_sub == true or cfg.hud.show_sub == nil
cfg.hud.expanded = cfg.hud.expanded == true or cfg.hud.expanded == nil
cfg.hud.pos_preset = tonumber(cfg.hud.pos_preset) or 0
cfg.hud.custom_x = tonumber(cfg.hud.custom_x) or 0.5
cfg.hud.custom_y = tonumber(cfg.hud.custom_y) or 0.9
cfg.glow.mode = tonumber(cfg.glow.mode) or 1
cfg.glow.intensity = tonumber(cfg.glow.intensity) or 0.55
cfg.glow.radius = tonumber(cfg.glow.radius) or 1.6
cfg.glow.r = tonumber(cfg.glow.r) or 0.35
cfg.glow.g = tonumber(cfg.glow.g) or 0.65
cfg.glow.b = tonumber(cfg.glow.b) or 1.0
cfg.notify.mode = tonumber(cfg.notify.mode) or 1
cfg.notify.duration = tonumber(cfg.notify.duration) or 3.0
cfg.hotkeys = cfg.hotkeys or {}

local function save_config()
    local ok = pcall(inicfg.save, cfg, CONFIG_PATH)
    if not ok then print("[cOBS] Не удалось сохранить настройки") end
end

----------------------------------------------------------------
-- SHA-256 на чистой Lua + bit (проверено тест-векторами NIST)
----------------------------------------------------------------
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, ror    = bit.lshift, bit.rshift, bit.ror
local tobit                  = bit.tobit

local SHA256_K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local HEXCHARS = "0123456789abcdef"
local function u32hex(v)
    if v < 0 then v = v + 4294967296 end
    local o = {}
    for i = 1, 8 do
        local d = v % 16
        o[9 - i] = HEXCHARS:sub(d + 1, d + 1)
        v = math.floor(v / 16)
    end
    return table.concat(o)
end

-- возвращает hex-строку SHA-256 от msg (байтовая строка)
local function sha256(msg)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }

    local len = #msg
    local s = msg .. "\128"
    while #s % 64 ~= 56 do s = s .. "\0" end

    local bits = len * 8
    local hi = math.floor(bits / 4294967296)
    local lo = bits % 4294967296
    for i = 3, 0, -1 do s = s .. string.char(math.floor(hi / 256 ^ i) % 256) end
    for i = 3, 0, -1 do s = s .. string.char(math.floor(lo / 256 ^ i) % 256) end

    local w = {}
    for pos = 1, #s, 64 do
        for i = 0, 15 do
            local j = pos + i * 4
            w[i + 1] = s:byte(j) * 16777216 + s:byte(j + 1) * 65536 + s:byte(j + 2) * 256 + s:byte(j + 3)
        end
        for i = 17, 64 do
            local x = w[i - 15]
            local y = w[i - 2]
            local s0 = bxor(bxor(ror(x, 7), ror(x, 18)), rshift(x, 3))
            local s1 = bxor(bxor(ror(y, 17), ror(y, 19)), rshift(y, 10))
            w[i] = tobit(w[i - 16] + s0 + w[i - 7] + s1)
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for i = 1, 64 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = tobit(h + S1 + ch + SHA256_K[i] + w[i])
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local t2 = tobit(S0 + maj)
            h, g, f, e, d, c, b, a = g, f, e, tobit(d + t1), c, b, a, tobit(t1 + t2)
        end
        H[1] = tobit(H[1] + a) H[2] = tobit(H[2] + b) H[3] = tobit(H[3] + c) H[4] = tobit(H[4] + d)
        H[5] = tobit(H[5] + e) H[6] = tobit(H[6] + f) H[7] = tobit(H[7] + g) H[8] = tobit(H[8] + h)
    end

    local out = {}
    for i = 1, 8 do out[i] = u32hex(H[i]) end
    return table.concat(out)
end

----------------------------------------------------------------
-- Base64 (проверено векторами RFC 4648)
----------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_encode(data)
    local out = {}
    local n = #data
    local i = 1
    while i <= n do
        local a = data:byte(i)
        local b = data:byte(i + 1)
        local c = data:byte(i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = B64:sub(math.floor(v / 262144) % 64 + 1, math.floor(v / 262144) % 64 + 1)
        out[#out + 1] = B64:sub(math.floor(v / 4096) % 64 + 1, math.floor(v / 4096) % 64 + 1)
        if b then
            out[#out + 1] = B64:sub(math.floor(v / 64) % 64 + 1, math.floor(v / 64) % 64 + 1)
        else
            out[#out + 1] = "="
        end
        if c then
            out[#out + 1] = B64:sub(v % 64 + 1, v % 64 + 1)
        else
            out[#out + 1] = "="
        end
        i = i + 3
    end
    return table.concat(out)
end

local function hex_to_bin(hex)
    local out = {}
    for i = 1, #hex, 2 do
        out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
    end
    return table.concat(out)
end

----------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------
local HAS_SAMPFUNCS = false

-- попапы в стиле Dynamic Island (всплывающие уведомления над островом)
local popup_list = {} -- { text = ..., r, g, b, t0 (сек, GetTickCount) }

local function popup_show(text, r, g, b)
    if #popup_list > 4 then table.remove(popup_list, 1) end
    popup_list[#popup_list + 1] = {
        text = text,
        r = r or 1, g = g or 1, b = b or 1,
        t0 = k32.GetTickCount() / 1000,
        dur = cfg.notify.duration or 3,
    }
end

-- сообщение: в чат SAMP (cp1251) и/или попап
local function notify(msg)
    local clean = msg:gsub("{%x%x%x%x%x%x}", "")
    if DEBUG_MODE then
        print(clean)
    end
    local mode = tonumber(cfg.notify.mode) or 1
    if (mode == 0 or mode == 2) and HAS_SAMPFUNCS then
        pcall(sampAddChatMessage, u8:decode(msg), 0xFFFFFFFF)
    end
    if mode == 1 or mode == 2 then
        local r, g, b = 1, 1, 1
        local hex = msg:match("^{(%x%x%x%x%x%x)}")
        if hex then
            r = tonumber(hex:sub(1, 2), 16) / 255
            g = tonumber(hex:sub(3, 4), 16) / 255
            b = tonumber(hex:sub(5, 6), 16) / 255
        end
        popup_show(clean, r, g, b)
    end
end

-- диагностика соединения (пишется в лог только при включённом DEBUG_MODE)
local function dbg(msg)
    if DEBUG_MODE then
        print("[cOBS] " .. msg)
    end
end



local function chat_active()
    if type(sampIsChatInputActive) == "function" then
        local ok, res = pcall(sampIsChatInputActive)
        if ok then return res end
    end
    return false
end

-- время из outputTimecode OBS: "HH:MM:SS.mmm" -> "HH:MM:SS"
local function clean_timecode(tc)
    if not tc or tc == "" then return "" end
    return tc:gsub("%.%d+$", "")
end

----------------------------------------------------------------
-- WinSock2 (встроен в Windows; подключаем через ffi)
----------------------------------------------------------------
ffi.cdef[[
    typedef unsigned short WORD;
    typedef unsigned int   u_int;
    typedef uintptr_t      SOCKET;

    typedef struct WSADATA {
        WORD        wVersion;
        WORD        wHighVersion;
        u_int       iMaxSockets;
        u_int       iMaxUdpDg;
        char       *lpVendorInfo;
        char        szDescription[257];
        char        szSystemStatus[129];
    } WSADATA;

    typedef struct sockaddr { unsigned short sa_family; char sa_data[14]; } sockaddr;
    typedef struct in_addr  { unsigned long s_addr; } in_addr;

    typedef struct sockaddr_in {
        short            sin_family;
        unsigned short   sin_port;
        struct in_addr   sin_addr;
        char             sin_zero[8];
    } sockaddr_in;

    typedef struct fd_set {
        u_int   fd_count;
        SOCKET  fd_array[64];
    } fd_set;

    typedef struct timeval { long tv_sec; long tv_usec; } timeval;

    int  WSAStartup(WORD wVersionRequested, WSADATA *lpWSAData);
    int  WSACleanup(void);
    SOCKET socket(int af, int type, int protocol);
    int  closesocket(SOCKET s);
    int  connect(SOCKET s, const struct sockaddr *name, int namelen);
    int  ioctlsocket(SOCKET s, long cmd, unsigned long *argp);
    int  select(int nfds, fd_set *readfds, fd_set *writefds,
                fd_set *exceptfds, const struct timeval *timeout);
    int  send(SOCKET s, const char *buf, int len, int flags);
    int  recv(SOCKET s, char *buf, int len, int flags);
    int  WSAGetLastError(void);
    unsigned short htons(unsigned short hostshort);
    unsigned long  inet_addr(const char *cp);
    ]]

local ws2 = ffi.load("ws2_32")

local AF_INET        = 2
local SOCK_STREAM    = 1
local IPPROTO_TCP    = 6
local FIONBIO        = 0x8004667E
local WSAEWOULDBLOCK = 10035
local INVALID_SOCKET = ffi.cast("SOCKET", -1)

local function make_fdset(sock)
    local fds = ffi.new("fd_set")
    fds.fd_count = 1
    fds.fd_array[0] = sock
    return fds
end

local function zero_tv()
    return ffi.new("timeval", { 0, 0 })
end

local function unmask(payload, key)
    local out = {}
    for i = 1, #payload do
        out[i] = string.char(bit.bxor(payload:byte(i), key:byte(((i - 1) % 4) + 1)))
    end
    return table.concat(out)
end

-- WebSocket-фрейм клиент -> сервер (всегда с маской)
local function ws_encode(opcode, payload)
    local len = #payload
    local head = { string.char(bit.bor(0x80, opcode)) }

    if len <= 125 then
        table.insert(head, string.char(bit.bor(0x80, len)))
    elseif len <= 0xFFFF then
        table.insert(head, string.char(bit.bor(0x80, 126)))
        table.insert(head, string.char(bit.band(bit.rshift(len, 8), 0xFF)))
        table.insert(head, string.char(bit.band(len, 0xFF)))
    else
        table.insert(head, string.char(bit.bor(0x80, 127)))
        local bytes = {}
        local tmp = len
        for i = 1, 8 do
            bytes[9 - i] = string.char(tmp % 256)
            tmp = math.floor(tmp / 256)
        end
        for i = 1, 8 do table.insert(head, bytes[i]) end
    end

    local mask = { math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255) }
    for i = 1, 4 do table.insert(head, string.char(mask[i])) end

    local out = { table.concat(head) }
    for i = 1, len do
        out[#out + 1] = string.char(bit.bxor(payload:byte(i), mask[((i - 1) % 4) + 1]))
    end
    return table.concat(out)
end

----------------------------------------------------------------
-- Клиент OBS (obs-websocket v5)
----------------------------------------------------------------
local obs = {
    sock = nil,
    state = "OFFLINE",        -- OFFLINE / CONNECTING / WAIT101 / FRAMES / WAIT_IDENT / READY
    buf = "",
    parse_pos = 1,
    recv_buf = ffi.new("char[4096]"),
    intentional_close = false,
    pending = {},
    req_seq = 0,
    hello_challenge = nil,
    hello_salt = nil,
    host = "127.0.0.1",
    port = 4455,
    password = "",
    handshake = "",

    is_recording = false,
    is_streaming = false,
    is_replay = false,
    is_vcam = false,
    record_timecode = "",
    stream_timecode = "",

    last_poll = 0,
    force_poll = false,
    last_error = "",
    mic_name = "",
    desktop_name = "",
    is_mic_muted = false,
    is_desktop_muted = false,
    has_mic = false,
    has_desktop = false,
}

function obs:connect()
    if self.state ~= "OFFLINE" then return end

    self.host = cfg.main.host
    self.port = tonumber(cfg.main.port) or 4455
    self.password = cfg.main.password

    self.handshake = "GET / HTTP/1.1\r\n" ..
        "Host: " .. self.host .. ":" .. self.port .. "\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ..
        "Sec-WebSocket-Version: 13\r\n" ..
        "Sec-WebSocket-Protocol: obswebsocket.json\r\n\r\n"

    local wsa = ffi.new("WSADATA")
    ws2.WSAStartup(0x0202, wsa)

    local s = ws2.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if s == INVALID_SOCKET then
        self.last_error = "не удалось создать сокет"
        notify("{E02222}OBS: не удалось создать сокет")
        return
    end

    local mode = ffi.new("unsigned long[1]", 1)
    ws2.ioctlsocket(s, FIONBIO, mode) -- неблокирующий режим (не вешает игру)

    local addr = ffi.new("sockaddr_in")
    addr.sin_family = AF_INET
    addr.sin_port = ws2.htons(self.port)
    addr.sin_addr.s_addr = ws2.inet_addr(self.host)

    ws2.connect(s, ffi.cast("struct sockaddr*", addr), ffi.sizeof(addr))

    self.sock = s
    self.state = "CONNECTING"
    self.buf = ""
    self.parse_pos = 1
    self.intentional_close = false
    self.pending = {}
    self.hello_challenge = nil
    self.hello_salt = nil
    self.last_error = ""
    self.last_poll = 0
    self.deadline = os.time() + 3

    dbg("connect: " .. self.host .. ":" .. self.port .. (self.password ~= "" and " (с паролем)" or " (БЕЗ пароля)"))

    if self.password == "" then
        local pw_hint = HAS_SAMPFUNCS and " Если OBS требует пароль — впиши его: /co -> «Пароль»" or ""
        notify("{FFA500}OBS: подключаюсь к " .. self.host .. ":" .. self.port .. "..." .. pw_hint)
    else
        notify("{FFA500}OBS: подключаюсь к " .. self.host .. ":" .. self.port .. " (с паролем)...")
    end
end

function obs:close()
    self.state = "OFFLINE"
    self.buf = ""
    self.parse_pos = 1
    self.is_recording = false
    self.is_streaming = false
    self.is_replay = false
    self.is_vcam = false
    self.record_timecode = ""
    self.stream_timecode = ""
    self.is_mic_muted = false
    self.is_desktop_muted = false
    if self.sock then
        ws2.closesocket(self.sock)
        self.sock = nil
    end
end

function obs:on_closed(text)
    if not self.intentional_close then
        self.last_error = "соединение закрыто" .. (text or "")
        notify("{E02222}OBS: соединение закрыто" .. (text or ""))
    end
    self:close()
end

function obs:send_frame(opcode, payload)
    if not self.sock then return end
    local frame = ws_encode(opcode, payload)
    ws2.send(self.sock, frame, #frame, 0)
end

function obs:send_text(text)
    self:send_frame(1, text) -- opcode 1 = text frame
end

function obs:drain_recv()
    while true do
        local n = ws2.recv(self.sock, self.recv_buf, 4096, 0)
        if n > 0 then
            self.buf = self.buf .. ffi.string(self.recv_buf, n)
            if n < 4096 then break end
        elseif n == 0 then
            self:on_closed(" (OBS закрыт?)")
            break
        else
            if ws2.WSAGetLastError() ~= WSAEWOULDBLOCK then
                self:on_closed(" (ошибка чтения)")
            end
            break
        end
    end
end

-- Достаёт один полный WS-фрейм из буфера
function obs:parse_next_frame()
    local buf = self.buf
    local pos = self.parse_pos
    if #buf - pos + 1 < 2 then return nil, nil, false end

    local b0 = buf:byte(pos)
    local b1 = buf:byte(pos + 1)
    local opcode = bit.band(b0, 0x0F)
    local masked = bit.band(b1, 0x80) ~= 0
    local len = bit.band(b1, 0x7F)
    pos = pos + 2

    if len == 126 then
        if #buf - pos + 1 < 2 then return nil, nil, false end
        len = bit.bor(bit.lshift(buf:byte(pos), 8), buf:byte(pos + 1))
        pos = pos + 2
    elseif len == 127 then
        if #buf - pos + 1 < 8 then return nil, nil, false end
        len = 0
        for i = 0, 7 do len = len * 256 + buf:byte(pos + i) end
        pos = pos + 8
    end

    local maskkey
    if masked then
        if #buf - pos + 1 < 4 then return nil, nil, false end
        maskkey = buf:sub(pos, pos + 3)
        pos = pos + 4
    end

    if #buf - pos + 1 < len then return nil, nil, false end
    local payload = buf:sub(pos, pos + len - 1)
    pos = pos + len

    if masked and maskkey then
        payload = unmask(payload, maskkey)
    end

    self.parse_pos = pos
    if self.parse_pos > 4096 then
        self.buf = self.buf:sub(self.parse_pos)
        self.parse_pos = 1
    end
    return opcode, payload, true
end

-- Авторизация по спецификации obs-websocket v5:
--   secret = base64( sha256( password + salt ) )
--   auth   = base64( sha256( secret + challenge ) )
function obs:identify()
    local msg
    if self.password ~= "" then
        local secret = base64_encode(hex_to_bin(sha256(self.password .. (self.hello_salt or ""))))
        local auth = base64_encode(hex_to_bin(sha256(secret .. (self.hello_challenge or ""))))
        msg = '{"op":1,"d":{"rpcVersion":1,"authentication":"' .. auth .. '"}}'
    else
        msg = '{"op":1,"d":{"rpcVersion":1}}'
    end
    self:send_text(msg)
    self.state = "WAIT_IDENT"
end

function obs:apply_status(kind, payload)
    local active = payload:match('"outputActive":(%a+)')
    if active then
        local b = active == "true"
        if kind == "record" then self.is_recording = b
        elseif kind == "stream" then self.is_streaming = b
        elseif kind == "replay" then self.is_replay = b
        elseif kind == "vcam" then self.is_vcam = b end
    end
    if kind == "record" or kind == "stream" then
        local tc = payload:match('"outputTimecode":"([^"]+)"')
        if tc then
            if kind == "record" then self.record_timecode = tc
            else self.stream_timecode = tc end
        end
    end
    if kind == "mic_mute" then
        local muted = payload:match('"inputMuted":%s*(%a+)')
        if muted then
            self.is_mic_muted = (muted == "true")
            self.has_mic = true
        end
    elseif kind == "desktop_mute" then
        local muted = payload:match('"inputMuted":%s*(%a+)')
        if muted then
            self.is_desktop_muted = (muted == "true")
            self.has_desktop = true
        end
    elseif kind == "special_inputs" then
        local mic = payload:match('"mic1":%s*"([^"]+)"')
        local desk = payload:match('"desktop1":%s*"([^"]+)"')
        if mic and mic ~= "" then
            self.mic_name = mic
            self.has_mic = true
            self:send_request("GetInputMute", "", "mic_mute", true, '{"inputName":"' .. mic .. '"}')
        end
        if desk and desk ~= "" then
            self.desktop_name = desk
            self.has_desktop = true
            self:send_request("GetInputMute", "", "desktop_mute", true, '{"inputName":"' .. desk .. '"}')
        end
    end
end

function obs:handle_response(payload)
    local id = payload:match('"requestId":"([^"]+)"')
    local req = self.pending[id]
    if not req then return end
    self.pending[id] = nil

    local success = payload:find('"result":true', 1, true) ~= nil
    if success then
        if req.kind then self:apply_status(req.kind, payload) end
        if not req.silent then
            notify("{27AE60}OBS: " .. req.label .. " - OK")
        end
    else
        if not req.silent then
            local comment = payload:match('"comment":%s*"([^"]+)"') or "неизвестная ошибка"
            notify("{E02222}OBS: " .. req.label .. " - ошибка: " .. comment)
        end
    end
end

function obs:handle_text(payload)
    local op = payload:match('"op":(%d)')
    if op == "0" then
        -- Hello
        self.hello_challenge = payload:match('"challenge":%s*"([^"]+)"')
        self.hello_salt = payload:match('"salt":%s*"([^"]+)"')
        dbg("Hello получен, требует авторизацию: " .. tostring(self.hello_challenge ~= nil))
        self:identify()

    elseif op == "2" then
        -- Identified
        if payload:find('"error"', 1, true) then
            self.last_error = "авторизация не прошла (проверьте пароль)"
            dbg("identify вернул ошибку")
            notify("{E02222}OBS: авторизация не прошла (проверьте пароль WebSocket в OBS и в настройках /co)")
            self.intentional_close = true
            self:close()
        else
            self.state = "READY"
            self.last_error = ""
            dbg("IDENTIFIED -> READY")
            notify("{27AE60}OBS: подключено! Открыть меню: /co")
            self:send_request("GetSpecialInputs", "", "special_inputs", true)
        end

    elseif op == "5" then
        -- Event: живой статус
        local ev = payload:match('"eventType":"([^"]+)"')
        local active = payload:match('"outputActive":(%a+)') == "true"
        if ev == "RecordStateChanged" then
            self.is_recording = active
            self.force_poll = true
        elseif ev == "ReplayBufferStateChanged" then
            self.is_replay = active
        elseif ev == "StreamStateChanged" then
            self.is_streaming = active
            self.force_poll = true
        elseif ev == "VirtualCamStateChanged" then
            self.is_vcam = active
        elseif ev == "InputMuteStateChanged" then
            local iname = payload:match('"inputName":%s*"([^"]+)"')
            local muted = payload:match('"inputMuted":%s*(%a+)') == "true"
            local mic = (cfg.audio and cfg.audio.mic_name ~= "") and cfg.audio.mic_name or self.mic_name
            local desk = (cfg.audio and cfg.audio.desktop_name ~= "") and cfg.audio.desktop_name or self.desktop_name
            if iname and (iname == mic or (mic == "" and iname:lower():find("mic"))) then
                self.is_mic_muted = muted
                self.has_mic = true
                self.mic_name = iname
                notify(muted and "{FFA500}OBS: [MIC] Микрофон ВЫКЛЮЧЕН (Mute)" or "{27AE60}OBS: [MIC] Микрофон ВКЛЮЧЕН")
            elseif iname and (iname == desk or (desk == "" and (iname:lower():find("desktop") or iname:lower():find("аудио")))) then
                self.is_desktop_muted = muted
                self.has_desktop = true
                self.desktop_name = iname
                notify(muted and "{FFA500}OBS: [AUDIO] Звуки ПК ВЫКЛЮЧЕНЫ (Mute)" or "{27AE60}OBS: [AUDIO] Звуки ПК ВКЛЮЧЕНЫ")
            end
        end

    elseif op == "7" then
        self:handle_response(payload)
    end
end

function obs:process_frames()
    while true do
        local opcode, payload, got = self:parse_next_frame()
        if not got then break end

        if opcode == 8 then
            -- Close
            local code = #payload >= 2 and (payload:byte(1) * 256 + payload:byte(2)) or nil
            local hint = ""
            if code == 4006 then hint = " (сервер не понял запрос — ошибка в скрипте?)"
            elseif code == 4009 then hint = " (неверный пароль WebSocket)"
            elseif code == 4010 then hint = " (несовместимая версия протокола)"
            elseif code == 4007 then hint = " (сообщение до Identify)"
            elseif code == 4011 then hint = " (сессия закрыта из OBS)"
            elseif code then hint = " (код " .. code .. ")" end
            self.on_closed(self, hint)
            break
        elseif opcode == 9 then
            self:send_frame(10, payload) -- pong
        elseif opcode == 1 then
            self:handle_text(payload)
        end
    end
end

function obs:update()
    if not self.sock then return end

    if self.state == "CONNECTING" then
        if os.time() > self.deadline then
            self.last_error = "нет соединения (OBS запущен? порт открыт?)"
            self.on_closed(self, " (нет соединения: OBS запущен? порт " .. self.port .. " открыт?)")
            return
        end
        local wf = make_fdset(self.sock)
        if ws2.select(0, nil, wf, nil, zero_tv()) > 0 then
            dbg("сокет готов к записи, шлю handshake")
            local n = ws2.send(self.sock, self.handshake, #self.handshake, 0)
            if n < 0 then
                self.last_error = "не удалось подключиться"
                dbg("send handshake failed, WSA err=" .. ws2.WSAGetLastError())
                self.on_closed(self, " (не удалось подключиться: OBS запущен? порт открыт?)")
                return
            end
            self.state = "WAIT101"
            self.deadline = os.time() + 3
        end
        return
    end

    local rf = make_fdset(self.sock)
    if ws2.select(0, rf, nil, nil, zero_tv()) > 0 then
        self:drain_recv()
    end
    if not self.sock then return end

    if self.state == "WAIT101" then
        if os.time() > self.deadline then
            self.last_error = "таймаут ответа сервера"
            self.on_closed(self, " (таймаут ответа сервера)")
            return
        end
        local pos = self.buf:find("\r\n\r\n", 1, true)
        if pos then
            local header = self.buf:sub(1, pos + 3)
            if not (header:find("101 Switching", 1, true) or header:find(" 101 ", 1, true)) then
                self.last_error = "сервер не ответил 101"
                self.on_closed(self, " (сервер не ответил 101)")
                return
            end
            self.buf = self.buf:sub(pos + 4)
            self.parse_pos = 1
            self.state = "FRAMES"
            self.deadline = os.time() + 3
            dbg("получен 101, перехожу к фреймам")
        end
    end

    if self.state == "FRAMES" or self.state == "WAIT_IDENT" or self.state == "READY" then
        if (self.state == "FRAMES" or self.state == "WAIT_IDENT") and os.time() > self.deadline then
            self.last_error = "сервер не завершил приветствие"
            self.on_closed(self, " (сервер не завершил приветствие)")
            return
        end
        self:process_frames()
    end

    -- живой опрос статусов (обновляет таймер записи в HUD)
    if self.state == "READY" then
        local now = os.time()
        if self.force_poll or now >= self.last_poll + 1 then
            self.force_poll = false
            self.last_poll = now
            self:send_request("GetRecordStatus", "", "record", true)
            self:send_request("GetStreamStatus", "", "stream", true)
            self:send_request("GetReplayBufferStatus", "", "replay", true)
            self:send_request("GetVirtualCamStatus", "", "vcam", true)
            local mic = (cfg.audio and cfg.audio.mic_name ~= "") and cfg.audio.mic_name or self.mic_name
            if mic ~= "" then
                self:send_request("GetInputMute", "", "mic_mute", true, '{"inputName":"' .. mic .. '"}')
            end
            local desk = (cfg.audio and cfg.audio.desktop_name ~= "") and cfg.audio.desktop_name or self.desktop_name
            if desk ~= "" then
                self:send_request("GetInputMute", "", "desktop_mute", true, '{"inputName":"' .. desk .. '"}')
            end
        end
    end
end

----------------------------------------------------------------
-- Команды / запросы
----------------------------------------------------------------
function obs:send_request(requestType, label, kind, silent, requestData)
    if self.state ~= "READY" then
        if not silent then notify("{E02222}OBS: нет соединения (открой /co -> Подключиться)") end
        return
    end
    self.req_seq = self.req_seq + 1
    local id = "ml" .. self.req_seq
    self.pending[id] = { label = label, kind = kind, silent = silent }
    local msg
    if requestData and requestData ~= "" then
        msg = '{"op":6,"d":{"requestType":"' .. requestType .. '","requestId":"' .. id .. '","requestData":' .. requestData .. '}}'
    else
        msg = '{"op":6,"d":{"requestType":"' .. requestType .. '","requestId":"' .. id .. '"}}'
    end
    self:send_text(msg)
end

function obs:cmd_toggle_record() self:send_request("ToggleRecord", "Запись", "record", false) self.force_poll = true end
function obs:cmd_toggle_replay() self:send_request("ToggleReplayBuffer", "Буфер повтора", "replay", false) end
function obs:cmd_save_replay()   self:send_request("SaveReplayBuffer", "Повтор сохранён", nil, false) end
function obs:cmd_toggle_stream() self:send_request("ToggleStream", "Стрим", "stream", false) self.force_poll = true end
function obs:cmd_toggle_vcam()    self:send_request("ToggleVirtualCam", "Виртуальная камера", "vcam", false) end
function obs:cmd_toggle_mic()
    local name = (cfg.audio and cfg.audio.mic_name ~= "") and cfg.audio.mic_name or self.mic_name
    if name == "" then name = "Mic/Aux" end
    self:send_request("ToggleInputMute", "Микрофон", "mic_mute", false, '{"inputName":"' .. name .. '"}')
end
function obs:cmd_toggle_desktop()
    local name = (cfg.audio and cfg.audio.desktop_name ~= "") and cfg.audio.desktop_name or self.desktop_name
    if name == "" then name = "Desktop Audio" end
    self:send_request("ToggleInputMute", "Звуки ПК", "desktop_mute", false, '{"inputName":"' .. name .. '"}')
end

function obs:reconnect()
    if self.state ~= "OFFLINE" then
        self.intentional_close = true
        self:close()
    end
    self:connect()
end


----------------------------------------------------------------
-- mimgui (интерфейс) — v2.4 Multi-Position HUD + Safe Clamping
----------------------------------------------------------------
local has_mimgui, imgui = pcall(require, "mimgui")
if not has_mimgui then
    function main()
        while not isSampAvailable() do wait(100) end
        sampAddChatMessage("{E02222}[cOBS Ошибка] Не найдена библиотека mimgui!", -1)
        sampAddChatMessage("{FFA500}[cOBS Инфо] Распакуйте архив cOBS_Full_Package.zip в папку moonloader", -1)
        print("[cOBS] ОШИБКА: mimgui не найден в moonloader/lib/mimgui! Скрипт остановлен.")
    end
    return
end
local mimgui = imgui

-- ═══════ Авто-масштабирование (базовое 1920×1080) ═══════
local cached_scale = 1.0
local cached_sw, cached_sh = 0, 0

local function update_scale(sw, sh)
    if sw == cached_sw and sh == cached_sh then return end
    cached_sw, cached_sh = sw, sh
    cached_scale = clamp(math.min(sw / 1920, sh / 1080), 0.4, 2.5)
end

local function S(px) return math.floor(px * cached_scale + 0.5) end

-- ═══════ Определение активного взаимодействия (чат / R-меню / диалоги) ═══════
local function is_interaction_active()
    if chat_active() then return true end
    if type(sampIsDialogActive) == "function" then
        local ok, res = pcall(sampIsDialogActive)
        if ok and res then return true end
    end
    if type(sampIsCursorActive) == "function" then
        local ok, res = pcall(sampIsCursorActive)
        if ok and res then return true end
    end
    return false
end

-- ═══════ Цвета-константы ═══════
local COL_RED    = imgui.ImVec4(0.91, 0.30, 0.24, 1)
local COL_GREEN  = imgui.ImVec4(0.30, 0.82, 0.36, 1)
local COL_ORANGE = imgui.ImVec4(1.00, 0.65, 0.00, 1)
local COL_BLUE   = imgui.ImVec4(0.30, 0.60, 1.00, 1)
local COL_WHITE  = imgui.ImVec4(1.00, 1.00, 1.00, 1)
local COL_GRAY   = imgui.ImVec4(0.72, 0.72, 0.72, 1)
local COL_YELLOW = imgui.ImVec4(1.00, 0.84, 0.00, 1)
local COL_ACCENT = imgui.ImVec4(0.30, 0.70, 1.00, 1)

local _v2_zero = imgui.ImVec2(0, 0)
local _v2_one  = imgui.ImVec2(1, 1)

local settings_open = false
local settings_tab  = 1
local hud_sub = nil
local tg_copied_timer = 0

-- ═══════ Защита от копирования и контроль авторства (Anti-Tamper) ═══════
local _AUTH_BYTES = {74, 105, 109, 105, 95, 72, 111, 112, 112, 101, 114} -- "Jimi_Hopper"
local _TG_BYTES   = {104, 116, 116, 112, 115, 58, 47, 47, 116, 46, 109, 101, 47, 43, 102, 54, 72, 53, 110, 95, 74, 65, 72, 79, 90, 104, 78, 84, 89, 54} -- "https://t.me/+f6H5n_JAHOZhNTY6"

local function _decode_raw(b)
    local s = {}
    for i = 1, #b do s[i] = string.char(b[i]) end
    return table.concat(s)
end

local function verify_author_integrity()
    local real_name = _decode_raw(_AUTH_BYTES)
    local real_tg   = _decode_raw(_TG_BYTES)
    local test_str  = tostring(AUTHOR_NAME) .. ":" .. tostring(AUTHOR_TG) .. ":cOBS_SECRET_SALT_2026"
    local computed  = sha256(test_str)

    if AUTHOR_NAME ~= real_name or AUTHOR_TG ~= real_tg or computed ~= AUTHOR_SEAL then
        AUTHOR_NAME = real_name
        AUTHOR_TG   = real_tg
        print("[cOBS Security] ВНИМАНИЕ: обнаружена модификация авторства!")
        print("[cOBS Security] Создатель: " .. real_name .. " | TG: " .. real_tg)
        if type(isSampAvailable) == "function" and isSampAvailable() then
            sampAddChatMessage("{E74C3C}[cOBS Защита] Пресечена попытка модификации авторских данных скрипта!", -1)
            sampAddChatMessage("{27AE60}[cOBS Защита] Создатель: " .. real_name .. " | TG: " .. real_tg, -1)
        end
        return false
    end
    return true
end

-- Последние вычисленные координаты HUD (для позиционирования попапов)
local last_hud_x, last_hud_y = 0, 0
local last_hud_w, last_hud_h = 200, 36
-- ═══════ Менеджер настраиваемых горячих клавиш (Кастомные & Комбинации) ═══════
local active_rebinding = nil

local HOTKEY_DEFS = {
    { id = "record",      name = "Запись видео",          default_key = vkeys.VK_F6  },
    { id = "mic",         name = "Микрофон (Mute)",       default_key = vkeys.VK_F5  },
    { id = "replay",      name = "Буфер повтора",         default_key = vkeys.VK_F7  },
    { id = "save",        name = "Сохранить повтор",      default_key = vkeys.VK_F8  },
    { id = "stream",      name = "Стрим / Эфир",          default_key = vkeys.VK_F9  },
    { id = "vcam",        name = "Вирт. камера",          default_key = vkeys.VK_F10 },
    { id = "menu",        name = "Меню настроек (/co)",   default_key = vkeys.VK_F11 },
}

local function get_hotkey(action_id)
    cfg.hotkeys = cfg.hotkeys or {}
    local raw_k = cfg.hotkeys[action_id .. "_key"]
    local k
    if raw_k ~= nil then
        k = tonumber(raw_k) or 0
    else
        for _, def in ipairs(HOTKEY_DEFS) do
            if def.id == action_id then k = def.default_key break end
        end
        k = k or 0
    end
    local function to_b(v) return v == true or v == 1 or v == "true" or v == "1" end
    return {
        key   = k,
        alt   = to_b(cfg.hotkeys[action_id .. "_alt"]),
        ctrl  = to_b(cfg.hotkeys[action_id .. "_ctrl"]),
        shift = to_b(cfg.hotkeys[action_id .. "_shift"]),
    }
end

local function set_hotkey(action_id, key_or_table, alt, ctrl, shift)
    cfg.hotkeys = cfg.hotkeys or {}
    if type(key_or_table) == "table" then
        cfg.hotkeys[action_id .. "_key"]   = tonumber(key_or_table.key) or 0
        cfg.hotkeys[action_id .. "_alt"]   = key_or_table.alt and true or false
        cfg.hotkeys[action_id .. "_ctrl"]  = key_or_table.ctrl and true or false
        cfg.hotkeys[action_id .. "_shift"] = key_or_table.shift and true or false
    else
        cfg.hotkeys[action_id .. "_key"]   = tonumber(key_or_table) or 0
        cfg.hotkeys[action_id .. "_alt"]   = alt and true or false
        cfg.hotkeys[action_id .. "_ctrl"]  = ctrl and true or false
        cfg.hotkeys[action_id .. "_shift"] = shift and true or false
    end
    save_config()
end

local function reset_hotkeys_to_default()
    cfg.hotkeys = cfg.hotkeys or {}
    for _, def in ipairs(HOTKEY_DEFS) do
        cfg.hotkeys[def.id .. "_key"]   = def.default_key
        cfg.hotkeys[def.id .. "_alt"]   = false
        cfg.hotkeys[def.id .. "_ctrl"]  = false
        cfg.hotkeys[def.id .. "_shift"] = false
    end
    save_config()
end

local function hotkey_display_text(action_id)
    if active_rebinding == action_id then
        return "[ Нажмите клавиши... (Esc - отм) ]"
    end
    local hk = get_hotkey(action_id)
    if not hk or hk.key == 0 then return "[ Не назначена ]" end
    local parts = {}
    if hk.ctrl then table.insert(parts, "Ctrl") end
    if hk.alt then table.insert(parts, "Alt") end
    if hk.shift then table.insert(parts, "Shift") end
    local kname = (vkeys.id_to_name and vkeys.id_to_name(hk.key)) or ("Key " .. tostring(hk.key))
    table.insert(parts, kname)
    return table.concat(parts, " + ")
end

local function is_modifier_down(mod)
    if mod == "Alt" then
        return isKeyDown(vkeys.VK_MENU) or isKeyDown(vkeys.VK_LMENU) or isKeyDown(vkeys.VK_RMENU)
    elseif mod == "Ctrl" then
        return isKeyDown(vkeys.VK_CONTROL) or isKeyDown(vkeys.VK_LCONTROL) or isKeyDown(vkeys.VK_RCONTROL)
    elseif mod == "Shift" then
        return isKeyDown(vkeys.VK_SHIFT) or isKeyDown(vkeys.VK_LSHIFT) or isKeyDown(vkeys.VK_RSHIFT)
    end
    return false
end

local function is_hotkey_pressed(action_id)
    local hk = get_hotkey(action_id)
    if not hk or hk.key == 0 then return false end

    local alt_req   = hk.alt
    local ctrl_req  = hk.ctrl
    local shift_req = hk.shift

    local alt_down   = is_modifier_down("Alt")
    local ctrl_down  = is_modifier_down("Ctrl")
    local shift_down = is_modifier_down("Shift")

    if alt_req ~= alt_down then return false end
    if ctrl_req ~= ctrl_down then return false end
    if shift_req ~= shift_down then return false end

    return isKeyJustPressed(hk.key)
end

-- ═══════ Буферы настроек ═══════
local host_buf, pass_buf
local port_buf, hud_width_b, hud_margin_b
local hud_enabled_b, autoconnect_b, show_pass_b
local hud_opacity_b, hud_show_sub_b, hud_expanded_b
local hud_preset_b, hud_custom_x_b, hud_custom_y_b
local glow_mode_b, glow_int_b, glow_rad_b, glow_col_b
local notify_mode_b, notify_dur_b
local mic_buf, desk_buf
local settings_p

local function init_ui_buffers()
    host_buf = imgui.new.char[128]()
    pass_buf = imgui.new.char[128]()
    mimgui.StrCopy(host_buf, cfg.main.host)
    mimgui.StrCopy(pass_buf, cfg.main.password)

    port_buf       = imgui.new.int[1](cfg.main.port)
    hud_width_b    = imgui.new.int[1](clamp(tonumber(cfg.hud.width) or 130, 50, 250))
    hud_margin_b   = imgui.new.int[1](cfg.hud.margin)
    hud_enabled_b  = imgui.new.bool[1](cfg.hud.enabled)
    autoconnect_b  = imgui.new.bool[1](cfg.main.autoconnect)
    show_pass_b    = imgui.new.bool[1](false)
    settings_p     = imgui.new.bool[1](true)

    hud_opacity_b  = imgui.new.float[1](cfg.hud.opacity)
    hud_show_sub_b = imgui.new.bool[1](cfg.hud.show_sub)
    hud_expanded_b = imgui.new.bool[1](cfg.hud.expanded)
    hud_preset_b   = imgui.new.int[1](cfg.hud.pos_preset or 0)
    hud_custom_x_b = imgui.new.float[1]((cfg.hud.custom_x or 0.5) * 100)
    hud_custom_y_b = imgui.new.float[1]((cfg.hud.custom_y or 0.9) * 100)

    glow_mode_b    = imgui.new.int[1](cfg.glow.mode)
    glow_int_b     = imgui.new.float[1](cfg.glow.intensity)
    glow_rad_b     = imgui.new.float[1](cfg.glow.radius)
    glow_col_b     = imgui.new.float[3](cfg.glow.r, cfg.glow.g, cfg.glow.b)
    notify_mode_b  = imgui.new.int[1](cfg.notify.mode)
    notify_dur_b   = imgui.new.float[1](cfg.notify.duration)

    mic_buf  = imgui.new.char[128]()
    desk_buf = imgui.new.char[128]()
    mimgui.StrCopy(mic_buf, cfg.audio and cfg.audio.mic_name or "")
    mimgui.StrCopy(desk_buf, cfg.audio and cfg.audio.desktop_name or "")
end

local function obs_state_text()
    if obs.state == "READY" then return "подключено" end
    if obs.state ~= "OFFLINE" then return "подключение..." end
    return (obs.last_error ~= "" and obs.last_error) or "нет соединения"
end

local function obs_state_color()
    if obs.state == "READY" then return COL_GREEN end
    if obs.state ~= "OFFLINE" then return COL_YELLOW end
    return COL_RED
end

-- ═══════ ВЕКТОРНЫЕ ИКОНКИ (100% совместимость, без эмодзи и без '?') ═══════
local function draw_mic_icon(dl, cx, cy, sz, col, muted, alpha)
    alpha = alpha or 1.0
    local a_col = col
    local body_w = sz * 0.44
    local body_h = sz * 0.65
    dl:AddRectFilled(
        imgui.ImVec2(cx - body_w * 0.5, cy - body_h * 0.55),
        imgui.ImVec2(cx + body_w * 0.5, cy + body_h * 0.15),
        a_col, body_w * 0.5, 15
    )
    local arc_w = sz * 0.72
    local arc_bot = cy + sz * 0.22
    dl:AddLine(imgui.ImVec2(cx - arc_w * 0.5, cy - sz * 0.05), imgui.ImVec2(cx - arc_w * 0.5, arc_bot), a_col, 1.5)
    dl:AddLine(imgui.ImVec2(cx - arc_w * 0.5, arc_bot), imgui.ImVec2(cx + arc_w * 0.5, arc_bot), a_col, 1.5)
    dl:AddLine(imgui.ImVec2(cx + arc_w * 0.5, cy - sz * 0.05), imgui.ImVec2(cx + arc_w * 0.5, arc_bot), a_col, 1.5)
    dl:AddLine(imgui.ImVec2(cx, arc_bot), imgui.ImVec2(cx, cy + sz * 0.48), a_col, 1.5)
    dl:AddLine(imgui.ImVec2(cx - sz * 0.26, cy + sz * 0.48), imgui.ImVec2(cx + sz * 0.26, cy + sz * 0.48), a_col, 1.5)

    if muted then
        local red_strike = imgui.U32(1.0, 0.22, 0.24, alpha)
        dl:AddLine(imgui.ImVec2(cx - sz * 0.52, cy + sz * 0.52), imgui.ImVec2(cx + sz * 0.52, cy - sz * 0.52), red_strike, 2.2)
    end
end

local function draw_speaker_icon(dl, cx, cy, sz, col, muted, alpha)
    alpha = alpha or 1.0
    local a_col = col
    dl:AddRectFilled(
        imgui.ImVec2(cx - sz * 0.45, cy - sz * 0.20),
        imgui.ImVec2(cx - sz * 0.20, cy + sz * 0.20),
        a_col, S(1), 15
    )
    dl:PathLineTo(imgui.ImVec2(cx - sz * 0.20, cy - sz * 0.20))
    dl:PathLineTo(imgui.ImVec2(cx + sz * 0.12, cy - sz * 0.44))
    dl:PathLineTo(imgui.ImVec2(cx + sz * 0.12, cy + sz * 0.44))
    dl:PathLineTo(imgui.ImVec2(cx - sz * 0.20, cy + sz * 0.20))
    dl:PathFillConvex(a_col)

    if not muted then
        dl:AddLine(imgui.ImVec2(cx + sz * 0.25, cy - sz * 0.18), imgui.ImVec2(cx + sz * 0.33, cy), a_col, 1.5)
        dl:AddLine(imgui.ImVec2(cx + sz * 0.33, cy), imgui.ImVec2(cx + sz * 0.25, cy + sz * 0.18), a_col, 1.5)
        dl:AddLine(imgui.ImVec2(cx + sz * 0.42, cy - sz * 0.32), imgui.ImVec2(cx + sz * 0.52, cy), a_col, 1.5)
        dl:AddLine(imgui.ImVec2(cx + sz * 0.52, cy), imgui.ImVec2(cx + sz * 0.42, cy + sz * 0.32), a_col, 1.5)
    else
        local red_col = imgui.U32(1.0, 0.22, 0.24, alpha)
        dl:AddLine(imgui.ImVec2(cx + sz * 0.22, cy - sz * 0.22), imgui.ImVec2(cx + sz * 0.50, cy + sz * 0.22), red_col, 2.0)
        dl:AddLine(imgui.ImVec2(cx + sz * 0.50, cy - sz * 0.22), imgui.ImVec2(cx + sz * 0.22, cy + sz * 0.22), red_col, 2.0)
    end
end

-- ═══════ Окно настроек (красивый темный UI) ═══════
local function section_header(text)
    imgui.Spacing()
    imgui.TextColored(COL_ACCENT, text)
    imgui.Separator()
    imgui.Spacing()
end

local function draw_settings_window()
    settings_p[0] = settings_open

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, S(12))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, S(6))
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding, S(5))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(S(16), S(14)))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(S(8), S(7)))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)

    imgui.PushStyleColor(imgui.Col.WindowBg,        imgui.ImVec4(0.07, 0.08, 0.12, 0.97))
    imgui.PushStyleColor(imgui.Col.Border,           imgui.ImVec4(0.22, 0.28, 0.44, 0.55))
    imgui.PushStyleColor(imgui.Col.TitleBg,          imgui.ImVec4(0.10, 0.12, 0.20, 1.00))
    imgui.PushStyleColor(imgui.Col.TitleBgActive,    imgui.ImVec4(0.13, 0.16, 0.28, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBg,          imgui.ImVec4(0.12, 0.14, 0.22, 0.85))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,   imgui.ImVec4(0.17, 0.20, 0.32, 0.95))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,    imgui.ImVec4(0.22, 0.26, 0.40, 1.00))
    imgui.PushStyleColor(imgui.Col.Button,           imgui.ImVec4(0.16, 0.22, 0.38, 0.90))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,    imgui.ImVec4(0.24, 0.32, 0.54, 1.00))
    imgui.PushStyleColor(imgui.Col.ButtonActive,     imgui.ImVec4(0.14, 0.18, 0.32, 1.00))
    imgui.PushStyleColor(imgui.Col.CheckMark,        imgui.ImVec4(0.35, 0.75, 1.00, 1.00))
    imgui.PushStyleColor(imgui.Col.SliderGrab,       imgui.ImVec4(0.32, 0.60, 0.95, 0.90))
    imgui.PushStyleColor(imgui.Col.SliderGrabActive, imgui.ImVec4(0.45, 0.72, 1.00, 1.00))
    imgui.PushStyleColor(imgui.Col.Header,           imgui.ImVec4(0.16, 0.22, 0.38, 0.80))
    imgui.PushStyleColor(imgui.Col.HeaderHovered,    imgui.ImVec4(0.24, 0.32, 0.54, 0.90))
    imgui.PushStyleColor(imgui.Col.HeaderActive,     imgui.ImVec4(0.14, 0.18, 0.32, 1.00))
    imgui.PushStyleColor(imgui.Col.Separator,        imgui.ImVec4(0.22, 0.30, 0.52, 0.40))
    imgui.PushStyleColor(imgui.Col.PopupBg,          imgui.ImVec4(0.09, 0.11, 0.18, 0.98))
    imgui.PushStyleColor(imgui.Col.Text,             imgui.ImVec4(0.90, 0.92, 0.98, 1.00))
    imgui.PushStyleColor(imgui.Col.TextDisabled,     imgui.ImVec4(0.52, 0.55, 0.62, 1.00))

    local win_w = S(450)
    local screen_w = (cached_sw and cached_sw > 0) and cached_sw or 1920
    local screen_h = (cached_sh and cached_sh > 0) and cached_sh or 1080
    local max_win_h = math.min(screen_h - S(60), S(520))

    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(win_w, S(300)), imgui.ImVec2(win_w, max_win_h))
    imgui.SetNextWindowPos(imgui.ImVec2((screen_w - win_w) * 0.5, math.max(S(30), (screen_h - max_win_h) * 0.5)), imgui.Cond.FirstUseEver)

    local flags = imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse
    if imgui.Begin("  cOBS Studio v2.5 by Jimi_Hopper  ##settings", settings_p, flags) then

        -- ═══════ Навигация по вкладкам (5 Tabs) ═══════
        local tab_names = { "OBS", "HUD", "LED", "Клавиши", "Автор" }
        local avail_w = imgui.GetContentRegionAvail and imgui.GetContentRegionAvail().x or (win_w - S(32))
        local tab_w = math.floor((avail_w - S(4) * (#tab_names - 1)) / #tab_names)
        local tab_h = S(28)

        for i, name in ipairs(tab_names) do
            if i > 1 then imgui.SameLine(0, S(4)) end
            local is_act = (settings_tab == i)
            if is_act then
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.20, 0.46, 0.86, 0.95))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.55, 0.98, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.15, 0.38, 0.72, 1.00))
                imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
            else
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.12, 0.15, 0.24, 0.75))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.22, 0.35, 0.90))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(0.10, 0.12, 0.20, 1.00))
                imgui.PushStyleColor(imgui.Col.Text,          imgui.ImVec4(0.65, 0.70, 0.82, 0.90))
            end
            if imgui.Button(name .. "##tab" .. i, imgui.ImVec2(tab_w, tab_h)) then
                settings_tab = i
            end
            imgui.PopStyleColor(4)
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local child_h = math.min(S(320), math.max(S(200), max_win_h - S(145)))
        if imgui.BeginChild("SettingsBody", imgui.ImVec2(0, child_h), false) then
            if settings_tab == 1 then
                -- ═══ ТАБ 1: OBS & ЗВУК ═══
                section_header("Подключение к OBS WebSocket")
                imgui.SetNextItemWidth(S(190))
                imgui.InputText("Хост", host_buf, 128)
                imgui.SetNextItemWidth(S(190))
                imgui.InputText("Пароль", pass_buf, 128,
                    show_pass_b[0] and 0 or imgui.InputTextFlags.Password)
                imgui.SameLine()
                imgui.Checkbox("##showpw", show_pass_b)
                imgui.SameLine()
                imgui.TextColored(COL_GRAY, "показать")
                imgui.SetNextItemWidth(S(120))
                imgui.InputInt("Порт", port_buf)

                imgui.Spacing()
                if obs.state == "READY" then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.60, 0.15, 0.18, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.75, 0.20, 0.24, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.48, 0.10, 0.12, 1.0))
                    if imgui.Button("  Отключиться  ", imgui.ImVec2(S(135), S(28))) then
                        obs.intentional_close = true
                        obs:close()
                    end
                    imgui.PopStyleColor(3)
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.50, 0.24, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.16, 0.65, 0.32, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.09, 0.40, 0.18, 1.0))
                    if imgui.Button("  Подключиться  ", imgui.ImVec2(S(135), S(28))) then
                        cfg.main.host = ffi.string(host_buf)
                        cfg.main.password = ffi.string(pass_buf)
                        if port_buf[0] > 0 and port_buf[0] <= 65535 then cfg.main.port = port_buf[0] end
                        save_config()
                        obs:connect()
                    end
                    imgui.PopStyleColor(3)
                end
                imgui.SameLine()
                if imgui.Button("  Переподключить  ", imgui.ImVec2(S(150), S(28))) then obs:reconnect() end

                imgui.Spacing()
                local sc = obs_state_color()
                local cp = imgui.GetCursorScreenPos()
                local dl = imgui.GetWindowDrawList()
                local dr = S(5)
                local lh = imgui.GetTextLineHeight()
                dl:AddCircleFilled(imgui.ImVec2(cp.x + dr + S(1), cp.y + lh * 0.5), dr, imgui.U32(sc.x, sc.y, sc.z, 1.0))
                imgui.Dummy(imgui.ImVec2(dr * 2 + S(6), lh))
                imgui.SameLine()
                imgui.TextColored(sc, "Статус: " .. obs_state_text())

                -- ═══ Управление звуком и микрофоном ═══
                section_header("Управление звуком и микрофоном (Медиа)")
                local abw = imgui.ImVec2(S(185), S(28))
                if obs.is_mic_muted then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.65, 0.14, 0.16, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.78, 0.18, 0.20, 1.0))
                    if imgui.Button("МИКРОФОН: ВЫКЛ##set", abw) then obs:cmd_toggle_mic() end
                    imgui.PopStyleColor(2)
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.50, 0.24, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.16, 0.65, 0.32, 1.0))
                    if imgui.Button("МИКРОФОН: ВКЛ##set", abw) then obs:cmd_toggle_mic() end
                    imgui.PopStyleColor(2)
                end
                imgui.SameLine()
                if obs.is_desktop_muted then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.65, 0.14, 0.16, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.78, 0.18, 0.20, 1.0))
                    if imgui.Button("ЗВУКИ ПК: ВЫКЛ##set", abw) then obs:cmd_toggle_desktop() end
                    imgui.PopStyleColor(2)
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.35, 0.58, 0.95))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.22, 0.44, 0.72, 1.0))
                    if imgui.Button("ЗВУКИ ПК: ВКЛ##set", abw) then obs:cmd_toggle_desktop() end
                    imgui.PopStyleColor(2)
                end

                imgui.Spacing()
                imgui.SetNextItemWidth(S(190))
                imgui.InputText("Имя микрофона", mic_buf, 128)
                imgui.SetNextItemWidth(S(190))
                imgui.InputText("Имя звуков ПК", desk_buf, 128)
                imgui.TextColored(COL_GRAY, "Если пусто - cOBS определяет источники в OBS автоматически")
                if obs.state == "READY" then
                    local mname = obs.mic_name ~= "" and obs.mic_name or "автопоиск"
                    local dname = obs.desktop_name ~= "" and obs.desktop_name or "автопоиск"
                    imgui.TextColored(COL_GRAY, "Активно: [Микрофон: " .. mname .. "] [Звуки: " .. dname .. "]")
                end

                -- ═══ Быстрые действия ═══
                section_header("Быстрые действия OBS")
                local bw = imgui.ImVec2(S(105), S(26))
                if imgui.Button("Запись##act", bw) then obs:cmd_toggle_record() end
                imgui.SameLine()
                if imgui.Button("Повтор##act", bw) then obs:cmd_toggle_replay() end
                imgui.SameLine()
                if imgui.Button("Сохр. повтор", bw) then obs:cmd_save_replay() end
                if imgui.Button("Стрим##act", bw) then obs:cmd_toggle_stream() end
                imgui.SameLine()
                if imgui.Button("Камера##act", bw) then obs:cmd_toggle_vcam() end

            elseif settings_tab == 2 then
                -- ═══ ТАБ 2: ВИД И РАСПОЛОЖЕНИЕ HUD ═══
                section_header("Отображение HUD")
                imgui.Checkbox("Показывать HUD", hud_enabled_b)
                imgui.Checkbox("Разворачивать при взаимодействии (чат / R-меню)", hud_expanded_b)
                imgui.Checkbox("Вторая строка статуса", hud_show_sub_b)

                section_header("Расположение на экране")
                imgui.SetNextItemWidth(S(240))
                imgui.ComboStr("Позиция на экране##pos", hud_preset_b,
                    "Снизу по центру (по умолч.)\0Сверху по центру\0Сверху слева\0Сверху справа\0Снизу слева\0Снизу справа\0Кастомное (ручные координаты)\0\0", -1)

                if hud_preset_b[0] == 6 then
                    imgui.SetNextItemWidth(S(200))
                    imgui.SliderFloat("Позиция по X, %", hud_custom_x_b, 0.0, 100.0, "%.1f%%")
                    imgui.SetNextItemWidth(S(200))
                    imgui.SliderFloat("Позиция по Y, %", hud_custom_y_b, 0.0, 100.0, "%.1f%%")
                    imgui.TextColored(COL_GRAY, "Остров защищён от вылета за границы экрана")
                else
                    imgui.SetNextItemWidth(S(190))
                    imgui.SliderInt("Отступ от края, px", hud_margin_b, 0, 300)
                end

                section_header("Размер и прозрачность")
                imgui.SetNextItemWidth(S(190))
                imgui.SliderInt("Размер (ширина), px", hud_width_b, 50, 250)
                imgui.SetNextItemWidth(S(190))
                imgui.SliderFloat("Прозрачность", hud_opacity_b, 0.25, 1.0, "%.2f", 1.0)

            elseif settings_tab == 3 then
                -- ═══ ТАБ 3: ПОДСВЕТКА И УВЕДОМЛЕНИЯ ═══
                section_header("ARGB LED Подсветка острова")
                imgui.SetNextItemWidth(S(190))
                imgui.ComboStr("Режим##glow", glow_mode_b, "Выкл\0Всегда (статичный)\0Авто (ночь)\0ARGB Радуга\0\0", -1)
                imgui.SetNextItemWidth(S(190))
                imgui.SliderFloat("Яркость##glow", glow_int_b, 0.0, 1.0, "%.2f", 1.0)
                imgui.SetNextItemWidth(S(190))
                imgui.SliderFloat("Размер свечения##glow", glow_rad_b, 0.6, 3.0, "%.1f", 1.0)
                if glow_mode_b[0] ~= 3 then
                    imgui.ColorEdit3("Цвет LED", glow_col_b, 0)
                else
                    imgui.TextColored(COL_ACCENT, "Цвет: динамическая плавная ARGB радуга")
                end

                section_header("Система уведомлений")
                imgui.SetNextItemWidth(S(240))
                imgui.ComboStr("Способ уведомлений##notif", notify_mode_b,
                    "Только в чат SA-MP\0Всплывающие UI уведомления\0Чат + Всплывающие уведомления\0\0", -1)
                imgui.SetNextItemWidth(S(190))
                imgui.SliderFloat("Длительность, сек", notify_dur_b, 1.0, 8.0, "%.1f", 1.0)

            elseif settings_tab == 4 then
                -- ═══ ТАБ 4: НАСТРОЙКА ГОРЯЧИХ КЛАВИШ ═══
                section_header("Настройка горячих клавиш")
                imgui.TextColored(COL_GRAY, "Кликните для назначения (одиночная клавиша или комбо: Alt+R)")
                imgui.TextColored(COL_GRAY, "Esc - отмена  |  Backspace / Del - очистить клавишу")
                imgui.Spacing()

                for _, def in ipairs(HOTKEY_DEFS) do
                    local is_capturing = (active_rebinding == def.id)
                    imgui.TextColored(COL_WHITE, def.name)
                    imgui.SameLine(S(210))

                    if is_capturing then
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.65, 0.15, 0.95))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.95, 0.75, 0.20, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.70, 0.50, 0.10, 1.0))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0, 0, 0, 1))
                    else
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.24, 0.40, 0.85))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.24, 0.35, 0.58, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.12, 0.18, 0.32, 1.0))
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.9, 0.95, 1.0, 1))
                    end

                    local label = hotkey_display_text(def.id) .. "##hk_" .. def.id
                    if imgui.Button(label, imgui.ImVec2(S(195), S(24))) then
                        if active_rebinding == def.id then
                            active_rebinding = nil
                        else
                            active_rebinding = def.id
                        end
                    end
                    imgui.PopStyleColor(4)
                end

                imgui.Spacing()
                if imgui.Button("  Сбросить все клавиши по умолчанию  ", imgui.ImVec2(S(280), S(26))) then
                    reset_hotkeys_to_default()
                    notify("{27AE60}cOBS: клавиши сброшены (F5-F11)")
                end

            elseif settings_tab == 5 then
                -- ═══ ТАБ 5: ОБ АВТОРЕ И ПОДДЕРЖКА ═══
                section_header("Создатель и официальный канал")
                verify_author_integrity()

                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.10, 0.13, 0.22, 0.70))
                imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, S(8))
                if imgui.BeginChild("AuthorBox", imgui.ImVec2(0, S(110)), true) then
                    imgui.TextColored(imgui.ImVec4(0.35, 0.75, 1.0, 1.0), "cOBS Studio v2.5")
                    imgui.SameLine()
                    imgui.TextColored(COL_GRAY, "- Интерактивный HUD для GTA SA")

                    imgui.TextColored(COL_WHITE, "Создатель:")
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0.95, 0.77, 0.20, 1.0), AUTHOR_NAME)

                    imgui.Spacing()
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.50, 0.85, 0.90))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.25, 0.60, 0.98, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.14, 0.40, 0.70, 1.0))
                    if imgui.Button("  Telegram-канал автора  ", imgui.ImVec2(S(185), S(26))) then
                        pcall(function() os.execute('explorer "' .. AUTHOR_TG .. '"') end)
                        notify("{27AE60}[cOBS] Открываем Telegram автора: " .. AUTHOR_TG)
                    end
                    imgui.PopStyleColor(3)

                    imgui.SameLine()
                    if imgui.Button("  Скопировать ссылку  ", imgui.ImVec2(S(160), S(26))) then
                        if type(setClipboardText) == "function" then
                            setClipboardText(AUTHOR_TG)
                            tg_copied_timer = os.clock() + 3.0
                            notify("{27AE60}[cOBS] Ссылка скопирована в буфер обмена!")
                        end
                    end

                    if os.clock() < tg_copied_timer then
                        imgui.TextColored(COL_GREEN, "[OK] Ссылка скопирована в буфер обмена!")
                    else
                        imgui.TextColored(COL_GRAY, "Канал: t.me/+f6H5n_JAHOZhNTY6")
                    end

                    imgui.EndChild()
                end
                imgui.PopStyleVar()
                imgui.PopStyleColor()
            end
            imgui.EndChild()
        end

        -- ═══════ Футер (всегда на виду) ═══════
        imgui.Separator()
        imgui.Spacing()
        imgui.Checkbox("Подключаться при запуске", autoconnect_b)
        imgui.SameLine(S(210))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.45, 0.75, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.24, 0.55, 0.90, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.14, 0.35, 0.62, 1.0))
        if imgui.Button("  Сохранить настройки  ", imgui.ImVec2(S(200), S(30))) then
            save_config()
            notify("{27AE60}cOBS: настройки сохранены (config\\cobs.ini)")
        end
        imgui.PopStyleColor(3)
    end
    imgui.End()
    imgui.PopStyleColor(20)
    imgui.PopStyleVar(6)

    -- Сохранение настроек из полей
    if port_buf[0] > 0 and port_buf[0] <= 65535 then cfg.main.port = port_buf[0] end
    cfg.main.host = ffi.string(host_buf)
    cfg.main.password = ffi.string(pass_buf)
    cfg.main.autoconnect = autoconnect_b[0]
    cfg.hud.enabled = hud_enabled_b[0]
    cfg.hud.width = hud_width_b[0]
    cfg.hud.margin = hud_margin_b[0]
    cfg.hud.opacity = hud_opacity_b[0]
    cfg.hud.show_sub = hud_show_sub_b[0]
    cfg.hud.expanded = hud_expanded_b[0]
    cfg.hud.pos_preset = hud_preset_b[0]
    cfg.hud.custom_x = clamp(hud_custom_x_b[0] / 100, 0.0, 1.0)
    cfg.hud.custom_y = clamp(hud_custom_y_b[0] / 100, 0.0, 1.0)
    cfg.glow.mode = glow_mode_b[0]
    cfg.glow.intensity = glow_int_b[0]
    cfg.glow.radius = glow_rad_b[0]
    cfg.glow.r, cfg.glow.g, cfg.glow.b = glow_col_b[0], glow_col_b[1], glow_col_b[2]
    cfg.notify.mode = notify_mode_b[0]
    cfg.notify.duration = notify_dur_b[0]
    cfg.audio = cfg.audio or {}
    cfg.audio.mic_name = ffi.string(mic_buf)
    cfg.audio.desktop_name = ffi.string(desk_buf)

    if not settings_p[0] then
        settings_p[0] = true
        settings_open = false
        save_config()
    end
end

----------------------------------------------------------------
-- Dynamic Island HUD
----------------------------------------------------------------
local hud_tex = nil
local hud_tex_tried = false
local hud_aspect = 3.5

local function png_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(24)
    f:close()
    if not head or #head < 24 or head:sub(1, 8) ~= "\137PNG\r\n\026\n" then return nil end
    local function be(b)
        return head:byte(b) * 16777216 + head:byte(b + 1) * 65536 + head:byte(b + 2) * 256 + head:byte(b + 3)
    end
    return be(17), be(21)
end

local function resolve_image_path()
    local wd = getWorkingDirectory()
    local candidates = {
        wd .. "\\" .. IMAGE_DIR .. "\\Rectangle 1.png",
        wd .. "\\" .. IMAGE_DIR .. "\\island.png",
        IMAGE_DIR .. "\\Rectangle 1.png",
    }
    for _, p in ipairs(candidates) do
        if doesFileExist(p) then return p end
    end
    local dir = wd .. "\\" .. IMAGE_DIR
    if doesDirectoryExist(dir) then
        local ok, files = pcall(listFiles, dir)
        if ok and type(files) == "table" then
            table.sort(files)
            for _, f in ipairs(files) do
                if tostring(f):lower():find("%.png$") then return dir .. "\\" .. tostring(f) end
            end
        end
    end
    return nil
end

local EMBEDDED_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAH4AAAAkCAYAAABPNo4ZAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAOdEVYdFNvZnR3YXJlAEZpZ21hnrGWYwAAAgVJREFUeAHtnDFSwkAYhR/Y2GFnJxcAOzvorJQT4An0Fla0NkppJV5ArezAyk64ACmtjJ2d+8guEzDBpGHI7vtmHuwkOzRvd//s5v+poTxNo3OjY6OOUcNKbI/YKLIaGz3ZdmFqJfpeWHUgdpGp0Z3RQ5HORYzvGg2NjiCqAGf+AP8MgL0N97h8XxvdQEt5laBXPfv9bvST1SlvxnN2Pxq1IaoMZ/8ZMuJ/lvE0/QVa2n0h0/x147k8vEGm+8YHkp1Y7C6sx3jG9FMI3zg02jd6dRfSM55btSGEz3DJn7CRNn4GLfG+wzjfYqNuL3C2y3T/ocf0emn8FUQo9PnBpZ6jYAYREi3O+B5EaPRovF66hEebxjchQqNL4/U0Hx4NPtx9QwRHHSJIaHwMERqxjA+TOY0fQ4RGROOnEKEx0ZFtmCyObF1utggDZuNEbjtXKBdbeAFz71cSMRjrdXzrN3PYzOn0Ac4lhO8MXCOdbMlYzyzbEwgfuUVSHLMgK736GUlBpPAHLvF8/b48rFs/q+eNvu0o/IBeruTUk6yXNJHtKPOrjyuk+FNClVc0ydExQpKEr5hfTRjTmUT7mXVzU7UsqyxZeeG2AAcQVYB+MVzfI6dSlpT5YwT+GEeQHvx2E56+8iBuVKRzGeMdPNtn3OjaNqXVYLt8IQnHLIdiHOdOrNRfofwCYrhTIj7sP7EAAAAASUVORK5CYII="

local function ensure_resources()
    local path = resolve_image_path()
    if path then return path end

    local dir = getWorkingDirectory() .. "\\" .. IMAGE_DIR
    if not doesDirectoryExist(dir) then
        pcall(createDirectory, dir)
    end
    local target = dir .. "\\Rectangle 1.png"
    local raw = b64_decode(EMBEDDED_PNG_B64)
    if raw then
        local f = io.open(target, "wb")
        if f then
            f:write(raw)
            f:close()
            if DEBUG_MODE then print("[cOBS] Автоматически создан ресурс: " .. target) end
            return target
        end
    end
    return nil
end

local function ensure_hud_texture()
    if hud_tex or hud_tex_tried then return end
    hud_tex_tried = true
    local path = ensure_resources()
    if not path then return end
    local ok, tex = pcall(mimgui.CreateTextureFromFile, path)
    if ok and tex then
        hud_tex = tex
        local w, h = png_dimensions(path)
        if w and h and h > 0 then hud_aspect = w / h end
    end
end

local function hud_content()
    local o = obs
    if o.state ~= "READY" then
        return nil, "OBS: нет связи", nil
    end
    local rec_tc = clean_timecode(o.record_timecode)
    local live_tc = clean_timecode(o.stream_timecode)
    local main_dot, main_text, main_kind
    if o.is_recording then
        main_kind = "rec"
        main_dot, main_text = COL_RED, "REC"
        if rec_tc ~= "" then main_text = "REC " .. rec_tc end
    elseif o.is_streaming then
        main_kind = "stream"
        main_dot, main_text = COL_GREEN, "LIVE"
        if live_tc ~= "" then main_text = "LIVE " .. live_tc end
    elseif o.is_replay then
        main_kind = "replay"
        main_dot, main_text = COL_ORANGE, "REPLAY"
    elseif o.is_vcam then
        main_kind = "vcam"
        main_dot, main_text = COL_BLUE, "VIRTUAL CAM"
    else
        main_kind = "idle"
        main_dot, main_text = COL_GREEN, "OBS"
    end

    local extras = {}
    if o.is_recording and main_kind ~= "rec" then extras[#extras + 1] = "запись " .. rec_tc end
    if o.is_streaming and main_kind ~= "stream" then extras[#extras + 1] = "стрим" end
    if o.is_replay and main_kind ~= "replay" then extras[#extras + 1] = "повтор" end

    local sub = table.concat(extras, " | ")
    if sub == "" then sub = nil end
    return main_dot, main_text, sub
end

-- ═══════ Шрифты ═══════
local hud_anim = 0
local HUD_EXTRA_H = 114

local hud_font_main, hud_font_sub = nil, nil
local fonts_ok = false
local _glyph_ranges = nil

local function load_hud_fonts_init()
    local ok, err = pcall(function()
        local dir = getFolderPath(0x14) .. "\\"
        local path
        for _, n in ipairs({"ariblk.ttf", "trebucbd.ttf", "arialbd.ttf", "segoeuib.ttf", "tahoma.ttf"}) do
            if doesFileExist(dir .. n) then path = dir .. n break end
        end
        if not path then
            if DEBUG_MODE then print("[cOBS] TTF не найден — используется системный шрифт") end
            return
        end
        local builder = imgui.ImFontGlyphRangesBuilder()
        builder:AddRanges(imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
        builder:AddText("•■●—…№")
        local ranges = imgui.ImVector_ImWchar()
        builder:BuildRanges(ranges)
        _glyph_ranges = ranges
        local fonts = imgui.GetIO().Fonts
        hud_font_main = fonts:AddFontFromFileTTF(path, 44, nil, ranges[0].Data)
        hud_font_sub  = fonts:AddFontFromFileTTF(path, 26, nil, ranges[0].Data)
        if hud_font_main or hud_font_sub then
            fonts_ok = true
            if DEBUG_MODE then print("[cOBS] Шрифты загружены: " .. path) end
        end
    end)
    if not ok then
        if DEBUG_MODE then print("[cOBS] Ошибка шрифтов: " .. tostring(err)) end
    end
end

if type(mimgui.OnInitialize) == "function" then
    mimgui.OnInitialize(load_hud_fonts_init)
end

local function text_w(font, px, text)
    if not font or not text or text == "" then return 0 end
    local ok, sz = pcall(function()
        return font:CalcTextSizeA(px, 100000, -1, text, nil, nil)
    end)
    if ok and sz then return sz.x end
    return imgui.CalcTextSize(text).x * (px / 14)
end

-- ═══════ Игровой час ═══════
local function game_hour()
    local ok, mins = pcall(memory.readuint, 0xB70152, 4, false)
    if ok and mins and mins > 0 and mins < 86400 then
        return math.floor(mins / 60) % 24
    end
    local ok2, h = pcall(getCurrentTime)
    if ok2 and h then return h end
    return nil
end

local function glow_active()
    local m = cfg.glow.mode
    if m == 0 then return false end
    if m == 1 or m == 3 then return true end
    local h = game_hour()
    return (h ~= nil) and (h < 6 or h >= 22)
end

-- ═══════ Расчёт цвета подсветки (статичный или ARGB Радуга) ═══════
local function get_glow_rgb()
    if cfg.glow.mode == 3 then
        local t = (k32.GetTickCount() / 1000) * 0.8
        local r = math.sin(t) * 0.45 + 0.55
        local g = math.sin(t + 2.0944) * 0.45 + 0.55
        local b = math.sin(t + 4.1888) * 0.45 + 0.55
        return r, g, b
    end
    return clamp(cfg.glow.r, 0, 1), clamp(cfg.glow.g, 0, 1), clamp(cfg.glow.b, 0, 1)
end

-- ═══════ Расчёт позиции HUD на экране со строгим анти-вылетом ═══════
local function get_hud_bounds(sw, sh, cur_w, cur_h)
    local PAD = S(8)
    local preset = cfg.hud.pos_preset or 0
    local margin = clamp(S(cfg.hud.margin or 28), 0, math.floor(sh * 0.4))
    local x, y = 0, 0

    if preset == 1 then
        -- 1: Сверху по центру (Dynamic Island стиль)
        x = (sw - cur_w) / 2
        y = margin
    elseif preset == 2 then
        -- 2: Сверху слева
        x = margin
        y = margin
    elseif preset == 3 then
        -- 3: Сверху справа
        x = sw - cur_w - margin
        y = margin
    elseif preset == 4 then
        -- 4: Снизу слева
        x = margin
        y = sh - cur_h - margin
    elseif preset == 5 then
        -- 5: Снизу справа
        x = sw - cur_w - margin
        y = sh - cur_h - margin
    elseif preset == 6 then
        -- 6: Кастомное ручное позиционирование (0..100% от доступной области)
        local px = clamp(cfg.hud.custom_x or 0.5, 0.0, 1.0)
        local py = clamp(cfg.hud.custom_y or 0.9, 0.0, 1.0)
        x = PAD + (sw - cur_w - PAD * 2) * px
        y = PAD + (sh - cur_h - PAD * 2) * py
    else
        -- 0: Снизу по центру (по умолчанию)
        x = (sw - cur_w) / 2
        y = sh - cur_h - margin
    end

    -- Жёсткое ограничение в экранных границах: защита от любого вылета за рамки
    x = clamp(x, PAD, sw - cur_w - PAD)
    y = clamp(y, PAD, sh - cur_h - PAD)

    return x, y
end

-- ═══════ Равномерная пропорциональная ARGB LED подсветка острова ═══════
local function draw_glow(px, py, pw, ph, cur_rad)
    local dl = imgui.GetBackgroundDrawList()
    local inten = clamp(cfg.glow.intensity, 0, 1)
    if inten <= 0 or pw <= 0 or ph <= 0 then return end

    local R, G, B = get_glow_rgb()
    local rad = cur_rad or math.min(ph * 0.5, S(22))
    local spread = clamp(cfg.glow.radius, 0.6, 3.0) * S(14)

    -- 16 концентрических слоёв мягкого затухающего свечения:
    -- Идеально симметричное и равномерное распределение со всех 4 сторон
    local layers = 16
    for k = layers, 1, -1 do
        local t = k / layers
        local exp = spread * t
        local a = inten * 0.18 * (1 - t) * (1 - t)
        if a > 0.002 then
            dl:AddRectFilled(
                imgui.ImVec2(px - exp, py - exp),
                imgui.ImVec2(px + pw + exp, py + ph + exp),
                imgui.U32(R, G, B, a),
                rad + exp,
                15
            )
        end
    end

    -- Аккуратный мягкий ободок-контур прямо по периметру корпуса (равномерно со всех сторон)
    local rim_a = inten * 0.28
    if rim_a > 0.01 then
        dl:AddRect(
            imgui.ImVec2(px - S(1.5), py - S(1.5)),
            imgui.ImVec2(px + pw + S(1.5), py + ph + S(1.5)),
            imgui.U32(R, G, B, rim_a),
            rad + S(1.5),
            15,
            S(2.0)
        )
    end
end

-- ═══════ Всплывающие уведомления (попапы) ═══════
local function draw_popups()
    if #popup_list == 0 then return end
    local io = imgui.GetIO()
    local sw, sh = io.DisplaySize.x, io.DisplaySize.y
    if sw <= 0 or sh <= 0 then return end

    local now = k32.GetTickCount() / 1000
    for i = #popup_list, 1, -1 do
        if now - popup_list[i].t0 > (popup_list[i].dur or 3) + 0.5 then
            table.remove(popup_list, i)
        end
    end
    if #popup_list == 0 then return end

    local p = popup_list[#popup_list]
    local age = now - p.t0
    if age > (p.dur or 3) + 0.5 then return end
    local a = math.min(1, age / 0.22)
    local out = math.max(0, 1 - math.max(0, age - (p.dur or 3)) / 0.5)
    a = math.min(a, out)

    local fdl = imgui.GetForegroundDrawList()
    local px = S(19)
    local tw = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, px, p.text) or imgui.CalcTextSize(p.text).x
    local padx, pady, dot = S(16), S(7), S(14)
    local pw = tw + padx * 2 + dot + S(8)
    local ph = px + pady * 2

    -- Позиционирование попапа относительно острова:
    -- Если остров в верхней половине экрана — попап появляется СНИЗУ острова.
    -- Если в нижней половине — попап появляется СВЕРХУ острова.
    local is_top = (last_hud_y < sh * 0.45)
    local y
    if is_top then
        y = last_hud_y + last_hud_h + S(10) + (1 - a) * S(14)
    else
        y = last_hud_y - ph - S(10) - (1 - a) * S(14)
    end
    local x = clamp(last_hud_x + (last_hud_w - pw) / 2, S(10), sw - pw - S(10))
    y = clamp(y, S(10), sh - ph - S(10))

    local rad = ph / 2
    fdl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + pw, y + ph), imgui.U32(0.04, 0.04, 0.06, 0.94 * a), rad, 15)
    fdl:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x + pw, y + ph), imgui.U32(0.35, 0.45, 0.65, 0.25 * a), rad, 15, 1.2)
    fdl:AddCircleFilled(imgui.ImVec2(x + padx + dot / 2, y + ph / 2), dot / 2, imgui.U32(p.r, p.g, p.b, a), 24)
    local tx = x + padx + dot + S(8)
    local ty = y + (ph - px * 0.72) / 2
    if hud_font_sub and fonts_ok then
        fdl:AddTextFontPtr(hud_font_sub, px, imgui.ImVec2(tx, ty), imgui.U32(1, 1, 1, a), p.text, nil, 0, nil)
    else
        fdl:AddText(imgui.ImVec2(tx, ty), imgui.U32(1, 1, 1, a), p.text, nil)
    end
end

-- ═══════ Отрисовка интерактивного HUD ═══════
local function draw_hud()
    ensure_hud_texture()
    local io = imgui.GetIO()
    local sw, sh = io.DisplaySize.x, io.DisplaySize.y
    if sw <= 0 or sh <= 0 then return end
    update_scale(sw, sh)

    -- Анимация разворачивания
    local interacting = is_interaction_active()
    local expand_target = (interacting and cfg.hud.expanded) and 1 or 0
    local dt = io.DeltaTime
    if dt <= 0 or dt > 0.1 then dt = 0.016 end
    hud_anim = hud_anim + (expand_target - hud_anim) * (1 - math.exp(-dt * 14))
    if math.abs(hud_anim) < 0.003 then hud_anim = 0 end
    if math.abs(hud_anim - 1) < 0.003 then hud_anim = 1 end

    -- Если чат открыт и остров развёрнут — включаем курсор mimgui для клика по кнопкам
    if hud_sub then
        hud_sub.HideCursor = not (chat_active() and cfg.hud.expanded and hud_anim > 0.6)
    end

    local op = clamp(cfg.hud.opacity, 0.2, 1)

    -- Содержимое свёрнутого состояния
    local dot_col, main_text, sub_text = hud_content()

    -- ═══ Расчёт размеров острова со сбалансированным диапазоном 50 .. 250 ═══
    local user_w = clamp(tonumber(cfg.hud.width) or 130, 50, 250)
    local scale_k = user_w / 130.0

    -- Высота и элементы острова масштабируются пропорционально
    local compact_h = math.max(S(20), math.floor(S(36) * scale_k + 0.5))
    local szo_comp  = math.max(S(9), math.floor(compact_h * 0.44 + 0.5))

    local tw_main = 0
    if main_text then
        tw_main = (hud_font_main and fonts_ok) and text_w(hud_font_main, szo_comp, main_text) or imgui.CalcTextSize(main_text).x
    end

    local dotw = math.max(S(5), math.floor(S(9) * scale_k + 0.5))
    local bsz  = math.max(S(12), math.floor(S(18) * scale_k + 0.5))

    local has_mic_mute = obs.is_mic_muted
    local has_desk_mute = obs.is_desktop_muted
    local badge_extra_w = 0
    if has_mic_mute and has_desk_mute then
        badge_extra_w = bsz * 2 + S(6)
    elseif has_mic_mute or has_desk_mute then
        badge_extra_w = bsz + S(4)
    end

    local total_content_w = (dot_col and (dotw + S(6)) or 0) + tw_main + badge_extra_w
    local min_pad = math.max(S(10), math.floor(S(22) * scale_k + 0.5))
    local min_needed_w = total_content_w + min_pad

    local base_cfg_w = S(user_w)
    local compact_w = math.max(base_cfg_w, min_needed_w)

    -- При разворачивании остров плавно расширяется
    local expanded_w = math.max(compact_w, math.floor(S(290) * math.max(0.75, scale_k)))
    local expanded_h = compact_h + math.floor(S(HUD_EXTRA_H) * math.max(0.75, scale_k))

    local cur_w = compact_w + (expanded_w - compact_w) * hud_anim
    local cur_h = compact_h + (expanded_h - compact_h) * hud_anim

    -- ═══ Расчёт позиции X и Y с защитой от вылета за границы экрана ═══
    local cur_x, cur_y = get_hud_bounds(sw, sh, cur_w, cur_h)
    local cur_rad = math.min(cur_h * 0.5, S(22))
    local is_top = (cur_y < sh * 0.45)

    -- Сохраняем актуальные координаты для попапов
    last_hud_x, last_hud_y = cur_x, cur_y
    last_hud_w, last_hud_h = cur_w, cur_h

    -- 1. ARGB LED подсветка под островом
    if cfg.glow.mode ~= 0 and glow_active() then
        draw_glow(cur_x, cur_y, cur_w, cur_h, cur_rad)
    end

    -- 2. Единое тело острова (матовое стекло со скруглением 15)
    local bgdl = imgui.GetBackgroundDrawList()
    local fdl  = imgui.GetForegroundDrawList()

    -- Фон острова
    bgdl:AddRectFilled(
        imgui.ImVec2(cur_x, cur_y),
        imgui.ImVec2(cur_x + cur_w, cur_y + cur_h),
        imgui.U32(0.04, 0.04, 0.06, 0.95 * op),
        cur_rad,
        15
    )

    -- Тонкая рамка
    bgdl:AddRect(
        imgui.ImVec2(cur_x, cur_y),
        imgui.ImVec2(cur_x + cur_w, cur_y + cur_h),
        imgui.U32(0.35, 0.45, 0.68, 0.24 * op),
        cur_rad,
        15,
        1.2
    )

    -- Верхний стеклянный блик (Стеклянный блик)
    if cur_rad > 8 then
        bgdl:AddLine(
            imgui.ImVec2(cur_x + cur_rad * 0.8, cur_y + 1),
            imgui.ImVec2(cur_x + cur_w - cur_rad * 0.8, cur_y + 1),
            imgui.U32(1.0, 1.0, 1.0, 0.12 * op),
            1.0
        )
    end

    -- ═══ РАЗВЁРНУТОЕ СОСТОЯНИЕ (hud_anim > 0.15) ═══
    if hud_anim > 0.15 and cfg.hud.expanded then
        -- 1. Верхняя инфо-строка со светящейся векторной точкой (без шрифтовых глифов)
        local info, cr, cg, cb
        if obs.state == "READY" and obs.is_recording then
            info = "ЗАПИСЬ  " .. clean_timecode(obs.record_timecode)
            cr, cg, cb = 1.0, 0.30, 0.30
            if obs.is_streaming then info = info .. " | LIVE" end
        elseif obs.state == "READY" and obs.is_streaming then
            info = "СТРИМ  " .. clean_timecode(obs.stream_timecode)
            cr, cg, cb = 0.30, 0.85, 0.40
        elseif obs.state == "READY" then
            info = "OBS подключен | Готов к записи"
            cr, cg, cb = 0.50, 0.85, 1.0
        else
            info = "OBS: нет связи"
            cr, cg, cb = 1.0, 0.45, 0.40
        end

        local info_size = S(16)
        local info_y = cur_y + S(11)
        local dot_r = S(4.5)
        local dot_gap = S(6)
        local tw_info = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, info_size, info) or imgui.CalcTextSize(info).x
        local total_info_w = (dot_r * 2 + dot_gap) + tw_info
        local start_x = cur_x + (cur_w - total_info_w) / 2

        fdl:AddCircleFilled(imgui.ImVec2(start_x + dot_r, info_y + info_size * 0.48), dot_r, imgui.U32(cr, cg, cb, 0.95 * hud_anim), 16)
        local text_start_x = start_x + dot_r * 2 + dot_gap

        if hud_font_sub and fonts_ok then
            fdl:AddTextFontPtr(hud_font_sub, info_size,
                imgui.ImVec2(text_start_x, info_y),
                imgui.U32(cr, cg, cb, 0.95 * hud_anim), info, nil, 0, nil)
        else
            fdl:AddText(imgui.ImVec2(text_start_x, info_y),
                imgui.U32(cr, cg, cb, 0.95 * hud_anim), info, nil)
        end

        -- 2. Интерактивные кнопки
        local interactive = hud_anim > 0.6 and interacting

        local wflags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove +
            imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings +
            imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoScrollWithMouse
        if not interactive then wflags = wflags + imgui.WindowFlags.NoInputs end

        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, _v2_zero)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
        imgui.SetNextWindowPos(imgui.ImVec2(cur_x, cur_y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(cur_w, cur_h), imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0)

        if imgui.Begin("##cOBS_hud_btn", nil, wflags) then
            -- Главная кнопка: ЗАПИСЬ
            local btn_w = cur_w - S(32)
            local btn_h = S(30)
            local btn_x = (cur_w - btn_w) / 2
            local btn_y = S(32)

            imgui.SetCursorPos(imgui.ImVec2(btn_x, btn_y))
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, S(8))
            local rec = (obs.state == "READY") and obs.is_recording

            if rec then
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.72, 0.12, 0.15, 0.95 * hud_anim))
                imgui.PushStyleColor(imgui.Col.ButtonHovered,  imgui.ImVec4(0.88, 0.18, 0.22, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,   imgui.ImVec4(0.60, 0.08, 0.10, 1.0))
                imgui.PushStyleColor(imgui.Col.Text,           imgui.ImVec4(1, 1, 1, hud_anim))
                if hud_font_sub and fonts_ok then imgui.PushFont(hud_font_sub) end
                if imgui.Button("[STOP]  ОСТАНОВИТЬ ЗАПИСЬ", imgui.ImVec2(btn_w, btn_h)) and interactive then
                    obs:cmd_toggle_record()
                end
                if hud_font_sub and fonts_ok then imgui.PopFont() end
                imgui.PopStyleColor(4)
            else
                imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.10, 0.58, 0.26, 0.95 * hud_anim))
                imgui.PushStyleColor(imgui.Col.ButtonHovered,  imgui.ImVec4(0.14, 0.72, 0.34, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,   imgui.ImVec4(0.08, 0.46, 0.20, 1.0))
                imgui.PushStyleColor(imgui.Col.Text,           imgui.ImVec4(1, 1, 1, hud_anim))
                if hud_font_sub and fonts_ok then imgui.PushFont(hud_font_sub) end
                if imgui.Button("[REC]  НАЧАТЬ ЗАПИСЬ", imgui.ImVec2(btn_w, btn_h)) and interactive then
                    obs:cmd_toggle_record()
                end
                if hud_font_sub and fonts_ok then imgui.PopFont() end
                imgui.PopStyleColor(4)
            end
            imgui.PopStyleVar(1) -- FrameRounding

            -- Второй ряд: Кнопки управления МЕДИА (Микрофон + Звуки ПК) с ВЕКТОРНЫМИ ИКОНКАМИ
            local audio_w = (btn_w - S(8)) / 2
            local audio_h = S(26)
            local audio_y = btn_y + btn_h + S(6)

            -- ═══ Кнопка Микрофона ═══
            local mic_x = btn_x
            imgui.SetCursorPos(imgui.ImVec2(mic_x, audio_y))
            local mic_clicked = imgui.InvisibleButton("##hud_btn_mic", imgui.ImVec2(audio_w, audio_h))
            local mic_hov = imgui.IsItemHovered()
            if mic_clicked and interactive then obs:cmd_toggle_mic() end

            local mic_bg = obs.is_mic_muted
                and imgui.U32(0.62, 0.12, 0.15, (mic_hov and 1.0 or 0.88) * hud_anim)
                or  imgui.U32(0.12, 0.45, 0.24, (mic_hov and 1.0 or 0.88) * hud_anim)
            local mic_border = imgui.U32(1, 1, 1, 0.15 * hud_anim)
            local mic_text = obs.is_mic_muted and "МИКР: ВЫКЛ" or "МИКР: ВКЛ"

            fdl:AddRectFilled(imgui.ImVec2(cur_x + mic_x, cur_y + audio_y),
                imgui.ImVec2(cur_x + mic_x + audio_w, cur_y + audio_y + audio_h), mic_bg, S(7), 15)
            fdl:AddRect(imgui.ImVec2(cur_x + mic_x, cur_y + audio_y),
                imgui.ImVec2(cur_x + mic_x + audio_w, cur_y + audio_y + audio_h), mic_border, S(7), 15, 1.0)

            -- Векторная иконка микрофона
            draw_mic_icon(fdl, cur_x + mic_x + S(17), cur_y + audio_y + audio_h * 0.5,
                S(15), imgui.U32(1, 1, 1, hud_anim), obs.is_mic_muted, hud_anim)

            -- Текст кнопки микрофона
            local mic_tw = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, S(13), mic_text) or imgui.CalcTextSize(mic_text).x
            local mic_tx = cur_x + mic_x + S(30) + (audio_w - S(34) - mic_tw) * 0.5
            local mic_ty = cur_y + audio_y + (audio_h - S(13) * 0.72) * 0.5
            if hud_font_sub and fonts_ok then
                fdl:AddTextFontPtr(hud_font_sub, S(13), imgui.ImVec2(mic_tx, mic_ty),
                    imgui.U32(1, 1, 1, hud_anim), mic_text, nil, 0, nil)
            else
                fdl:AddText(imgui.ImVec2(mic_tx, mic_ty), imgui.U32(1, 1, 1, hud_anim), mic_text, nil)
            end

            -- ═══ Кнопка Звуков ПК ═══
            local desk_x = btn_x + audio_w + S(8)
            imgui.SetCursorPos(imgui.ImVec2(desk_x, audio_y))
            local desk_clicked = imgui.InvisibleButton("##hud_btn_desk", imgui.ImVec2(audio_w, audio_h))
            local desk_hov = imgui.IsItemHovered()
            if desk_clicked and interactive then obs:cmd_toggle_desktop() end

            local desk_bg = obs.is_desktop_muted
                and imgui.U32(0.62, 0.12, 0.15, (desk_hov and 1.0 or 0.88) * hud_anim)
                or  imgui.U32(0.16, 0.35, 0.58, (desk_hov and 1.0 or 0.88) * hud_anim)
            local desk_border = imgui.U32(1, 1, 1, 0.15 * hud_anim)
            local desk_text = obs.is_desktop_muted and "ЗВУКИ: ВЫКЛ" or "ЗВУКИ: ВКЛ"

            fdl:AddRectFilled(imgui.ImVec2(cur_x + desk_x, cur_y + audio_y),
                imgui.ImVec2(cur_x + desk_x + audio_w, cur_y + audio_y + audio_h), desk_bg, S(7), 15)
            fdl:AddRect(imgui.ImVec2(cur_x + desk_x, cur_y + audio_y),
                imgui.ImVec2(cur_x + desk_x + audio_w, cur_y + audio_y + audio_h), desk_border, S(7), 15, 1.0)

            -- Векторная иконка динамика
            draw_speaker_icon(fdl, cur_x + desk_x + S(17), cur_y + audio_y + audio_h * 0.5,
                S(15), imgui.U32(1, 1, 1, hud_anim), obs.is_desktop_muted, hud_anim)

            -- Текст кнопки звуков
            local desk_tw = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, S(13), desk_text) or imgui.CalcTextSize(desk_text).x
            local desk_tx = cur_x + desk_x + S(30) + (audio_w - S(34) - desk_tw) * 0.5
            local desk_ty = cur_y + audio_y + (audio_h - S(13) * 0.72) * 0.5
            if hud_font_sub and fonts_ok then
                fdl:AddTextFontPtr(hud_font_sub, S(13), imgui.ImVec2(desk_tx, desk_ty),
                    imgui.U32(1, 1, 1, hud_anim), desk_text, nil, 0, nil)
            else
                fdl:AddText(imgui.ImVec2(desk_tx, desk_ty), imgui.U32(1, 1, 1, hud_anim), desk_text, nil)
            end

            -- ═══ Третий ряд: Быстрые действия (Сохранить повтор + Настройки) ═══
            local rep_x = btn_x
            local rep_y = audio_y + audio_h + S(6)
            imgui.SetCursorPos(imgui.ImVec2(rep_x, rep_y))
            local rep_clicked = imgui.InvisibleButton("##hud_btn_save_rep", imgui.ImVec2(audio_w, audio_h))
            local rep_hov = imgui.IsItemHovered()
            if rep_clicked and interactive then obs:cmd_save_replay() end

            local rep_bg = imgui.U32(0.38, 0.18, 0.58, (rep_hov and 1.0 or 0.88) * hud_anim)
            local rep_border = imgui.U32(1, 1, 1, 0.15 * hud_anim)
            local rep_text = (audio_w < S(105)) and "ПОВТОР" or "СОХРАНИТЬ ПОВТОР"

            fdl:AddRectFilled(imgui.ImVec2(cur_x + rep_x, cur_y + rep_y),
                imgui.ImVec2(cur_x + rep_x + audio_w, cur_y + rep_y + audio_h), rep_bg, S(7), 15)
            fdl:AddRect(imgui.ImVec2(cur_x + rep_x, cur_y + rep_y),
                imgui.ImVec2(cur_x + rep_x + audio_w, cur_y + rep_y + audio_h), rep_border, S(7), 15, 1.0)

            local rep_tw = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, S(12), rep_text) or imgui.CalcTextSize(rep_text).x
            local rep_tx = cur_x + rep_x + (audio_w - rep_tw) * 0.5
            local rep_ty = cur_y + rep_y + (audio_h - S(12) * 0.72) * 0.5
            if hud_font_sub and fonts_ok then
                fdl:AddTextFontPtr(hud_font_sub, S(12), imgui.ImVec2(rep_tx, rep_ty),
                    imgui.U32(1, 1, 1, hud_anim), rep_text, nil, 0, nil)
            else
                fdl:AddText(imgui.ImVec2(rep_tx, rep_ty), imgui.U32(1, 1, 1, hud_anim), rep_text, nil)
            end

            -- ═══ Кнопка открытия Настроек (/co) ═══
            local set_x = btn_x + audio_w + S(8)
            imgui.SetCursorPos(imgui.ImVec2(set_x, rep_y))
            local set_clicked = imgui.InvisibleButton("##hud_btn_open_set", imgui.ImVec2(audio_w, audio_h))
            local set_hov = imgui.IsItemHovered()
            if set_clicked and interactive then toggle_settings() end

            local set_bg = imgui.U32(0.18, 0.22, 0.32, (set_hov and 1.0 or 0.88) * hud_anim)
            local set_border = imgui.U32(1, 1, 1, 0.15 * hud_anim)
            local set_text = (audio_w < S(105)) and "МЕНЮ /co" or "НАСТРОЙКИ (/co)"

            fdl:AddRectFilled(imgui.ImVec2(cur_x + set_x, cur_y + rep_y),
                imgui.ImVec2(cur_x + set_x + audio_w, cur_y + rep_y + audio_h), set_bg, S(7), 15)
            fdl:AddRect(imgui.ImVec2(cur_x + set_x, cur_y + rep_y),
                imgui.ImVec2(cur_x + set_x + audio_w, cur_y + rep_y + audio_h), set_border, S(7), 15, 1.0)

            local set_tw = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, S(12), set_text) or imgui.CalcTextSize(set_text).x
            local set_tx = cur_x + set_x + (audio_w - set_tw) * 0.5
            local set_ty = cur_y + rep_y + (audio_h - S(12) * 0.72) * 0.5
            if hud_font_sub and fonts_ok then
                fdl:AddTextFontPtr(hud_font_sub, S(12), imgui.ImVec2(set_tx, set_ty),
                    imgui.U32(1, 1, 1, hud_anim), set_text, nil, 0, nil)
            else
                fdl:AddText(imgui.ImVec2(set_tx, set_ty), imgui.U32(1, 1, 1, hud_anim), set_text, nil)
            end
        end
        imgui.End()
        imgui.PopStyleVar(3) -- WindowPadding, BorderSize, WindowRounding

        -- 3. Нижняя строка подсказок горячих клавиш (динамические клавиши)
        local hint_text = string.format("%s микр | %s запись | %s повтор | /co",
            hotkey_display_text("mic"),
            hotkey_display_text("record"),
            hotkey_display_text("save"))
        local hint_size = S(11)
        local hint_y = cur_y + cur_h - S(14)
        if hud_font_sub and fonts_ok then
            local tw_hint = text_w(hud_font_sub, hint_size, hint_text)
            fdl:AddTextFontPtr(hud_font_sub, hint_size,
                imgui.ImVec2(cur_x + (cur_w - tw_hint) / 2, hint_y),
                imgui.U32(0.65, 0.68, 0.75, 0.70 * hud_anim), hint_text, nil, 0, nil)
        else
            local tw_hint = imgui.CalcTextSize(hint_text).x
            fdl:AddText(
                imgui.ImVec2(cur_x + (cur_w - tw_hint) / 2, hint_y),
                imgui.U32(0.65, 0.68, 0.75, 0.70 * hud_anim), hint_text, nil)
        end
    end

    -- ═══ СВЁРНУТОЕ СОСТОЯНИЕ (hud_anim < 0.8) ═══
    if hud_anim < 0.8 then
        local alpha_compact = (1 - hud_anim * 1.25) * op
        if alpha_compact > 0.02 and main_text then
            local tx = cur_x + (cur_w - total_content_w) / 2
            local ty = cur_y + (cur_h - szo_comp) * 0.44

            -- 1. Точка статуса
            if dot_col then
                fdl:AddCircleFilled(
                    imgui.ImVec2(tx + dotw * 0.5, cur_y + cur_h * 0.5),
                    szo_comp * 0.20,
                    imgui.U32(dot_col.x, dot_col.y, dot_col.z, alpha_compact),
                    24
                )
                tx = tx + dotw + S(6)
            end

            -- 2. Основной текст (REC 00:00:11 или OBS)
            if hud_font_main and fonts_ok then
                fdl:AddTextFontPtr(hud_font_main, szo_comp, imgui.ImVec2(tx, ty),
                    imgui.U32(1, 1, 1, alpha_compact), main_text, nil, 0, nil)
            else
                fdl:AddText(imgui.ImVec2(tx, ty), imgui.U32(1, 1, 1, alpha_compact), main_text, nil)
            end
            tx = tx + tw_main + S(7)

            -- 3. Аккуратные компактные бейджи выключенного звука (векторные иконки в рубиновом микро-бейдже)
            local bicon_sz = math.max(S(8), math.floor(S(12) * scale_k + 0.5))
            if has_mic_mute then
                local by = cur_y + (cur_h - bsz) * 0.5
                fdl:AddRectFilled(imgui.ImVec2(tx, by), imgui.ImVec2(tx + bsz, by + bsz),
                    imgui.U32(0.75, 0.12, 0.16, 0.35 * alpha_compact), S(5), 15)
                fdl:AddRect(imgui.ImVec2(tx, by), imgui.ImVec2(tx + bsz, by + bsz),
                    imgui.U32(1.0, 0.25, 0.25, 0.70 * alpha_compact), S(5), 15, 1.0)
                draw_mic_icon(fdl, tx + bsz * 0.5, by + bsz * 0.5, bicon_sz,
                    imgui.U32(1, 1, 1, alpha_compact), true, alpha_compact)
                tx = tx + bsz + S(4)
            end

            if has_desk_mute then
                local by = cur_y + (cur_h - bsz) * 0.5
                fdl:AddRectFilled(imgui.ImVec2(tx, by), imgui.ImVec2(tx + bsz, by + bsz),
                    imgui.U32(0.75, 0.12, 0.16, 0.35 * alpha_compact), S(5), 15)
                fdl:AddRect(imgui.ImVec2(tx, by), imgui.ImVec2(tx + bsz, by + bsz),
                    imgui.U32(1.0, 0.25, 0.25, 0.70 * alpha_compact), S(5), 15, 1.0)
                draw_speaker_icon(fdl, tx + bsz * 0.5, by + bsz * 0.5, bicon_sz,
                    imgui.U32(1, 1, 1, alpha_compact), true, alpha_compact)
                tx = tx + bsz + S(4)
            end

            -- Вторая строка (если включена и позволяет высота)
            if sub_text and cfg.hud.show_sub and cur_h >= S(30) then
                local szo_sub = math.max(S(8), math.floor(cur_h * 0.24 + 0.5))
                local sw_sub = (hud_font_sub and fonts_ok) and text_w(hud_font_sub, szo_sub, sub_text) or imgui.CalcTextSize(sub_text).x
                local sub_y = cur_y + cur_h * 0.74 - szo_sub * 0.5
                if hud_font_sub and fonts_ok then
                    fdl:AddTextFontPtr(hud_font_sub, szo_sub,
                        imgui.ImVec2(cur_x + (cur_w - sw_sub) / 2, sub_y),
                        imgui.U32(0.85, 0.88, 0.95, alpha_compact * 0.85), sub_text, nil, 0, nil)
                else
                    fdl:AddText(imgui.ImVec2(cur_x + (cur_w - sw_sub) / 2, sub_y),
                        imgui.U32(0.85, 0.88, 0.95, alpha_compact * 0.85), sub_text, nil)
                end
            end
        end
    end
end

----------------------------------------------------------------
-- Горячие клавиши
----------------------------------------------------------------
local KEY_MIC    = vkeys.VK_F5  -- Управление микрофоном (Mute/Unmute)
local KEY_RECORD = vkeys.VK_F6  -- Запись (Start/Stop)
local KEY_REPLAY = vkeys.VK_F7  -- Буфер повтора (Start/Stop)
local KEY_SAVE   = vkeys.VK_F8  -- Сохранить повтор (ShadowPlay)
local KEY_STREAM = vkeys.VK_F9  -- Стрим (Start/Stop)
local KEY_VCAM   = vkeys.VK_F10 -- Виртуальная камера
local KEY_MENU   = vkeys.VK_F11 -- Меню настроек /co

----------------------------------------------------------------
-- main
----------------------------------------------------------------
local function toggle_settings()
    if settings_open then save_config() end
    settings_open = not settings_open
end

function main()
    math.randomseed(os.time())

    while not isSampAvailable() do wait(100) end
    wait(500)

    verify_author_integrity()

    HAS_SAMPFUNCS = type(sampGetCurrentServerName) == "function"

    init_ui_buffers()

    -- Окно настроек: без HideCursor = true, чтобы курсор работал
    local set_sub = imgui.OnFrame(function() return settings_open end, function() draw_settings_window() end)

    -- HUD: поверх всего, курсор включается динамически только когда чат открыт для клика
    hud_sub = imgui.OnFrame(function() return cfg.hud.enabled end, function() draw_hud() end)
    hud_sub.HideCursor = true

    -- Попапы: без курсора
    local pop_sub = imgui.OnFrame(function()
        return cfg.notify.mode == 1 or cfg.notify.mode == 2
    end, function()
        draw_popups()
    end)
    pop_sub.HideCursor = true

    -- Чат-команда /co
    if HAS_SAMPFUNCS then
        sampRegisterChatCommand("co", toggle_settings)
    end

    if cfg.main.autoconnect then obs:connect() end

    notify("{27AE60}cOBS Studio v2.5 by Jimi_Hopper | /co - меню | ТГ: t.me/+f6H5n_JAHOZhNTY6")

    while true do
        wait(0)
        obs:update()

        -- Обработка интерактивного переназначения клавиш в окне настроек
        if active_rebinding then
            if isKeyJustPressed(vkeys.VK_ESCAPE) then
                active_rebinding = nil
            elseif isKeyJustPressed(vkeys.VK_BACK) or isKeyJustPressed(vkeys.VK_DELETE) then
                set_hotkey(active_rebinding, 0, false, false, false)
                active_rebinding = nil
            else
                for vk = 1, 255 do
                    local is_mouse = (vk == 1 or vk == 2 or vk == 4)
                    local is_mod = (vk == vkeys.VK_MENU or vk == vkeys.VK_LMENU or vk == vkeys.VK_RMENU or
                                    vk == vkeys.VK_CONTROL or vk == vkeys.VK_LCONTROL or vk == vkeys.VK_RCONTROL or
                                    vk == vkeys.VK_SHIFT or vk == vkeys.VK_LSHIFT or vk == vkeys.VK_RSHIFT)
                    if not is_mouse and not is_mod and isKeyJustPressed(vk) then
                        local alt_down   = is_modifier_down("Alt")
                        local ctrl_down  = is_modifier_down("Ctrl")
                        local shift_down = is_modifier_down("Shift")
                        set_hotkey(active_rebinding, vk, alt_down, ctrl_down, shift_down)
                        active_rebinding = nil
                        break
                    end
                end
            end
        end

        -- Меню настроек /co
        if not chat_active() and not active_rebinding then
            if is_hotkey_pressed("menu") then
                toggle_settings()
            end
        end

        -- Быстрые действия OBS (когда чат и меню настроек закрыты)
        if not settings_open and not chat_active() and not active_rebinding then
            if is_hotkey_pressed("mic")    then obs:cmd_toggle_mic() end
            if is_hotkey_pressed("record") then obs:cmd_toggle_record() end
            if is_hotkey_pressed("replay") then obs:cmd_toggle_replay() end
            if is_hotkey_pressed("save")   then obs:cmd_save_replay() end
            if is_hotkey_pressed("stream") then obs:cmd_toggle_stream() end
            if is_hotkey_pressed("vcam")   then obs:cmd_toggle_vcam() end
        end
    end
end

addEventHandler('onScriptTerminate', function(scr)
    if scr == thisScript() then
        save_config()
        if obs.sock then
            obs.intentional_close = true
            obs:close()
        end
    end
end)

----------------------------------------------------------------
-- Экспорт для других скриптов
----------------------------------------------------------------
function obs_toggle_record()  obs:cmd_toggle_record() end
function obs_toggle_replay()  obs:cmd_toggle_replay() end
function obs_save_replay()    obs:cmd_save_replay() end
function obs_toggle_stream()  obs:cmd_toggle_stream() end
function obs_toggle_vcam()    obs:cmd_toggle_vcam() end
function obs_toggle_mic()     obs:cmd_toggle_mic() end
function obs_toggle_desktop() obs:cmd_toggle_desktop() end
function obs_is_mic_muted()   return obs.is_mic_muted end
function obs_is_desktop_muted() return obs.is_desktop_muted end
