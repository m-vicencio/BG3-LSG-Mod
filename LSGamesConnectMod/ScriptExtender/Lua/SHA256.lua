--- Implementación pura de SHA-256 y HMAC-SHA-256 en Lua 5.4.
--
-- Cumple con FIPS 180-4. Todos los valores intermedios se tratan como
-- enteros de 32 bits sin signo mediante la máscara ``& 0xFFFFFFFF``.
--
-- Uso:
--   local SHA256 = Ext.Require("SHA256.lua")
--   local hex    = SHA256.hash("hola mundo")
--   local mac    = SHA256.hmac("clave_secreta", "mensaje")

local SHA256 = {}

-- ---------------------------------------------------------------------------
-- Constantes SHA-256 (FIPS 180-4 §4.2.2)
-- ---------------------------------------------------------------------------

-- Primeros 32 bits de la parte fraccionaria de las raíces cúbicas
-- de los primeros 64 números primos.
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- Valores iniciales del hash H₀ (primeros 32 bits de la parte fraccionaria
-- de las raíces cuadradas de los primeros 8 números primos).
local H_INIT = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

-- ---------------------------------------------------------------------------
-- Utilidades de bit a 32 bits
-- ---------------------------------------------------------------------------

--- Enmascara un entero de 64 bits a 32 bits sin signo.
--
-- @param x number  Valor entero.
-- @return  number  Los 32 bits inferiores de x.
local function u32(x)
    return x & 0xFFFFFFFF
end

--- Rotación a la derecha de 32 bits.
--
-- @param x number  Valor de 32 bits.
-- @param n number  Cantidad de posiciones a rotar.
-- @return  number  Resultado de 32 bits.
local function rr32(x, n)
    return u32((x >> n) | (x << (32 - n)))
end

-- ---------------------------------------------------------------------------
-- Núcleo SHA-256
-- ---------------------------------------------------------------------------

--- Calcula SHA-256 y devuelve el digest como cadena de 32 bytes crudos.
--
-- @param msg string  Mensaje de longitud arbitraria.
-- @return   string   32 bytes de digest (no codificados en hex).
local function _sha256_raw(msg)
    -- Paso 1: relleno del mensaje (FIPS 180-4 §5.1.1)
    local len    = #msg
    local bitlen = len * 8          -- longitud en bits (cabe en int64 para strings prácticos)

    -- Añadir bit '1' seguido de ceros hasta que len ≡ 56 (mod 64)
    msg = msg .. "\x80"
    while (#msg % 64) ~= 56 do
        msg = msg .. "\x00"
    end

    -- Añadir longitud original en bits como big-endian de 64 bits
    for i = 7, 0, -1 do
        msg = msg .. string.char(u32(bitlen >> (i * 8)) & 0xFF)
    end

    -- Paso 2: inicializar el estado del hash
    local h = {}
    for i = 1, 8 do h[i] = H_INIT[i] end

    -- Paso 3: procesar cada bloque de 512 bits (64 bytes)
    for blk = 1, #msg, 64 do
        -- Expandir el bloque en 64 palabras de 32 bits (message schedule)
        local w = {}
        for i = 0, 15 do
            local o = blk + i * 4
            w[i] = u32(
                (string.byte(msg, o)     << 24) |
                (string.byte(msg, o + 1) << 16) |
                (string.byte(msg, o + 2) <<  8) |
                 string.byte(msg, o + 3)
            )
        end
        for i = 16, 63 do
            local s0 = rr32(w[i-15], 7) ~ rr32(w[i-15], 18) ~ (w[i-15] >> 3)
            local s1 = rr32(w[i-2], 17) ~ rr32(w[i-2],  19) ~ (w[i-2]  >> 10)
            w[i] = u32(w[i-16] + s0 + w[i-7] + s1)
        end

        -- Inicializar variables de trabajo con el hash actual
        local a, b, c, d, e, f, g, hh =
            h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]

        -- Ronda de compresión (64 iteraciones)
        for i = 0, 63 do
            local S1    = rr32(e, 6) ~ rr32(e, 11) ~ rr32(e, 25)
            local ch    = (e & f) ~ (~e & g)          -- NOT de e en 32 bits queda correcto al hacer AND con g (32 bits)
            local temp1 = u32(hh + S1 + ch + K[i + 1] + w[i])
            local S0    = rr32(a, 2) ~ rr32(a, 13) ~ rr32(a, 22)
            local maj   = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = u32(S0 + maj)

            hh = g;  g = f;  f = e
            e  = u32(d + temp1)
            d  = c;  c = b;  b = a
            a  = u32(temp1 + temp2)
        end

        -- Actualizar estado del hash
        h[1] = u32(h[1] + a);  h[2] = u32(h[2] + b)
        h[3] = u32(h[3] + c);  h[4] = u32(h[4] + d)
        h[5] = u32(h[5] + e);  h[6] = u32(h[6] + f)
        h[7] = u32(h[7] + g);  h[8] = u32(h[8] + hh)
    end

    -- Serializar el resultado como 32 bytes en big-endian
    local out = ""
    for i = 1, 8 do
        for shift = 24, 0, -8 do
            out = out .. string.char(u32(h[i] >> shift) & 0xFF)
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- API pública
-- ---------------------------------------------------------------------------

--- Calcula SHA-256 y devuelve el digest en hexadecimal.
--
-- @param msg string  Datos de entrada.
-- @return   string   64 caracteres hexadecimales en minúsculas.
function SHA256.hash(msg)
    return (_sha256_raw(msg):gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

--- Calcula HMAC-SHA-256 siguiendo RFC 2104.
--
-- Reproduce exactamente el comportamiento de ``hmac.new(key, msg, hashlib.sha256).hexdigest()``
-- de Python para garantizar interoperabilidad con la firma del middleware.
--
-- @param key string  Clave secreta compartida (texto plano UTF-8).
-- @param msg string  Mensaje a autenticar.
-- @return   string   64 caracteres hexadecimales en minúsculas.
function SHA256.hmac(key, msg)
    local BLOCK = 64    -- tamaño de bloque de SHA-256 en bytes

    -- Si la clave supera el tamaño de bloque, se comprime con hash
    if #key > BLOCK then
        key = _sha256_raw(key)
    end
    -- Rellenar la clave con ceros hasta completar el bloque
    key = key .. string.rep("\x00", BLOCK - #key)

    -- Construir ipad y opad según RFC 2104
    local ipad = key:gsub(".", function(c)
        return string.char(string.byte(c) ~ 0x36)
    end)
    local opad = key:gsub(".", function(c)
        return string.char(string.byte(c) ~ 0x5C)
    end)

    -- HMAC = SHA256( opad || SHA256( ipad || message ) )
    local inner = _sha256_raw(ipad .. msg)
    return SHA256.hash(opad .. inner)
end

return SHA256
