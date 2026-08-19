# Protocolo HID de haptics — ROG/Xbox Ally X (ASUS)

Reverse-engineered a partir de tráfico USB de Armoury Crate.
VID: `0x0B05` (ASUS) · PID: `0x1B4C`

## Interfaz correcta

De las 7 interfaces HID que expone el dispositivo compuesto, la que acepta
estos comandos es:

```
HID\VID_0B05&PID_1B4C&MI_02&Col01
Usage Page: 0xFF31 (vendor-specific ASUS)
Usage: 0x76
FeatureReportByteLength: 64
```

Se accede vía `HidD_SetFeature` (Windows), Report ID `0x5A`.

Las otras 6 interfaces (`MI_00`, `MI_04`, `MI_05`, y las demás collections
de `MI_02`) o no soportan Feature Reports, o devuelven
`ERROR_INVALID_FUNCTION` / `ERROR_INVALID_PARAMETER` — no son el canal
correcto para esto.

## Estructura de los paquetes

Todos los paquetes son Feature Reports de 64 bytes, Report ID `0x5A`
(primer byte del buffer), seguido de sub-comando `0xD0 0x05`.

### Paquete de ARRANQUE (arma el motor + intensidad)

```
byte:  0    1    2    3    4          5          6..63
       5a   d0   05   02   [SELECTOR] [INTENSIDAD] 00 00 00 ...
```

- **SELECTOR** (byte 4): qué motor
  - `1` = rumble motor izquierdo (motor normal, abajo)
  - `2` = rumble motor derecho (motor normal, abajo)
  - `3` = **trigger izquierdo** ← el que nos importa para adaptive triggers
  - `4` = trigger derecho
  - `≥5` = inválido, no hace nada

- **INTENSIDAD** (byte 5): `0x00`–`0xFF`, escala lineal confirmada
  (`0x20` < `0x40` < `0x80` < `0xC0` < `0xFF`, progresión perceptible).
  `0x00` = apagado.

### Paquetes de "PASO" (necesarios para que el efecto se aplique)

Después del paquete de arranque, hay que mandar 1 o más paquetes de paso:

```
byte:  0    1    2    3    4   5..63
       5a   d0   05   03   [N] 00 00 ...
```

Donde `N` va de `1` hasta la cantidad de pasos (probamos con 4, funciona).
Rol exacto de la cantidad de pasos: todavía no confirmado con certeza —
hipótesis actual es que se relaciona con duración/commit del efecto, no
con selección de motor (eso ya lo descartamos).

**IMPORTANTE — timing FINAL confirmado (optimizado):**
- Post-arranque: **0ms** de delay (confirmado, funciona perfecto).
- Entre pasos: **0ms** de delay (confirmado, funciona perfecto).
- Para uso en tiempo real: mandar **1 solo paso** por actualización (no 4)
  — sostiene más tiempo por sí solo, así que alcanza con resendear cada
  ~20ms si la posición del trigger cambió. Con esto, el lag percibido es
  **prácticamente imperceptible** en pruebas reales con el gatillo físico.
- El timing original (130ms / 4ms, copiado de la captura de Armoury
  Crate) era innecesariamente conservador — probablemente porque
  Armoury Crate no está optimizado para baja latencia en tiempo real,
  nosotros sí lo necesitamos para esto.

### Apagar un motor

Repetir el paquete de arranque con el mismo SELECTOR e INTENSIDAD `0x00`,
seguido de al menos 1 paso.

**CRÍTICO:** el motor queda vibrando indefinidamente si no se apaga
explícitamente — no hay timeout automático conocido. Cualquier código que
use esto DEBE apagar el motor al terminar, incluso en casos de error
(try/finally o equivalente).

## Otros sub-comandos descubiertos (familia `0xD0 0x05`)

Además de `0x02` (arranque) y `0x03` (paso), el byte 3 acepta al menos:

- **`0x01`** = **test de todos los motores**: dispara una secuencia rápida
  y automática que activa, en orden, los 4 motores (rumble izq, rumble
  der, trigger izq, trigger der) y se apaga solo al terminar. Parece un
  comando de auto-diagnóstico/demo, posiblemente el que usa Armoury Crate
  al conectar el dispositivo por primera vez. No requiere paquete de paso
  separado — con mandar el paquete solo alcanza.
- `0x00`, `0x04`, `0x05` — probados, sin efecto perceptible observado.

## Bytes sin uso conocido

Se probó explícitamente poner `0xAA` en los bytes 6-15 del paquete de
arranque, y en los bytes 5-15 del paquete de paso (uno a la vez, todo lo
demás en su valor conocido). **Ningún cambio perceptible en ningún caso**
— son padding inerte hasta donde pudimos confirmar, al menos en el rango
probado (6-15). El resto del buffer (16-63) no se probó exhaustivamente
pero es razonable asumir el mismo comportamiento dado el patrón.

- [x] ¿Qué pasa si se llama la secuencia completa en loop continuo
      (cada 20-50ms)? **CONFIRMADO: funciona fluido, reenviando cada 50ms
      (~20Hz).** Sin resender, el dispositivo tiene un timeout interno de
      seguridad y el motor se apaga solo después de un pulso breve.
- [ ] Curva de intensidad específica para los triggers (izq/der) — solo
      confirmamos la curva de intensidad en los motores normales, no
      explícitamente en los triggers.
- [x] Asimetría física notada: el motor izquierdo pega notablemente más
      fuerte/brusco que el derecho a la misma intensidad — CONFIRMADO
      como comportamiento esperable del hardware de rumble (motores
      físicamente distintos, como en cualquier control tipo Xbox).
      Armoury Crate lo compensa con una curva de calibración interna que
      nuestro protocolo crudo no aplica. **No afecta a los triggers** —
      se probó selector 3 vs 4 a la misma intensidad cruda (0x40, 0x80,
      0xFF) y se sintieron parejos. No hace falta calibración por lado
      para los triggers.
- [x] Rol exacto de la cantidad de "pasos" en el paquete de paso.
      **CONFIRMADO (parcialmente):** no es un contador lineal de duración.
      Con 1-2 pasos, el efecto sostiene más tiempo por sí solo. Con 4+
      pasos, el efecto termina rápido y de forma idéntica sin importar
      cuántos pasos de más se manden (4, 8, 12, 20 pasos se sintieron
      igual de cortos). Hipótesis: el dispositivo implementa un envelope
      interno de pocas etapas (tipo ataque/sostenido/liberación) y cada
      paso avanza una etapa; más allá de la última etapa, los pasos
      extra no hacen nada. Para sostener el efecto en tiempo real,
      conviene mandar POCOS pasos (1-2) y resendear periódicamente, en
      vez de mandar 4+ pasos repetidamente.
- [x] Timing mínimo viable: **CONFIRMADO — se puede bajar a 0ms de delay**
      tanto después del arranque como entre pasos, sin que falle nada.
      El timing original (130ms / 4ms) copiado de Armoury Crate era
      innecesariamente conservador. Esto reduce significativamente la
      latencia percibida en uso en tiempo real.
- [ ] Cómo mapear los distintos tipos de efecto de adaptive trigger del
      DualSense (Feedback, Weapon, Vibration, etc, cada uno con sus
      parámetros) a esta única dimensión de "intensidad simple" que
      tenemos disponible acá — dado que la Ally X solo tiene motores de
      vibración, no resistencia real.

## ⚠️ Bug conocido / decisión de diseño

Al apagar el selector `1` (rumble izquierdo) vía este protocolo (intensidad
`0x00`), en al menos un caso el motor se quedó vibrando con intensidad alta
en vez de apagarse. Causa exacta sin confirmar.

**Decisión: no usar este protocolo para los motores de rumble normales
(selector 1 y 2).** Esos dos ya se controlan de forma confiable y probada
con `XInputSetState` clásico (funciona perfecto, es la API estándar de
Windows para esto). Este protocolo HID custom se usa **exclusivamente
para los triggers (selector 3 y 4)**, que es lo único que XInput nunca
pudo controlar y el motivo real de todo este reverse engineering.

Como red de seguridad adicional: cualquier código que use este protocolo
debe poder llamar a `XInputSetState(0, {0,0})` como "botón de pánico" para
los motores de rumble en caso de que algo se trabe, independientemente del
estado del protocolo HID custom.

