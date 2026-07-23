// NavImu.qml — Estimador de actitud y posición por IMU (giroscopio + acelerómetro)
//
// Implementa el filtro complementario de Mahony sobre el grupo SO(3):
//   - Cuaternión de actitud integrado con lecturas del giroscopio
//   - Corrección de inclinación (roll/pitch) vía acelerómetro (gravedad)
//   - Extracción de yaw como cambio de heading en el frame mundo
//   - Integración de posición: heading_IMU × velocidad_GPS → lat/lon
//
// Uso:
//   imu.start(headingRad, lat, lon)   // al activar DR (heading GPS inicial)
//   imu.stop()                         // al salir de DR
//   imu.advance(speedMs, dt)           // en cada tick DR para avanzar posición
//   imu.headingRad / imuLat / imuLon  // resultados
//
// El heading estimado es relativo al frame del dispositivo al inicio de la calibración.
// La escala y signo del giroscopio (GYRO_SCALE, YAW_SIGN) pueden necesitar ajuste
// según la plataforma y orientación física del dispositivo en el vehículo.

import QtQuick 2.7
import QtSensors 5.9
import Qt.labs.settings 1.0

Item {
    id: root
    visible: false
    width:   0
    height:  0

    // ── API pública ──────────────────────────────────────────────────────────
    // active: true durante DR (start/stop). Los sensores también corren mientras
    // gpsActive=true para calibrar gyroScale/yawSign con GPS antes del primer DR.
    property bool active:        false   // true = sensores activos (DR o calibración GPS)
    property bool gpsActive:     false   // poner a true al arrancar para pre-calibrar
    property bool calibrated:    false   // true tras CALIB_N muestras de accel
    property real calibProgress: 0.0    // 0.0 → 1.0

    property real headingRad:    0.0    // heading estimado (rad; convenio _headRad)
    property real imuLat:        0.0    // latitud DR estimada
    property real imuLon:        0.0    // longitud DR estimada

    // start(): inicializa el estado y activa los sensores.
    // initHeadRad: heading GPS en el momento de activar DR (rad).
    function start(initHeadRad, lat, lon) {
        _yaw0      = initHeadRad
        headingRad = initHeadRad
        imuLat     = lat
        imuLon     = lon
        _q         = [1.0, 0.0, 0.0, 0.0]
        _eInt      = [0.0, 0.0, 0.0]
        _lastTs    = -1.0
        _lastAx = 0.0; _lastAy = 0.0; _lastAz = 9.8
        calibrated    = false
        calibProgress = 0.0
        _calibN   = 0
        _calibAx  = 0.0; _calibAy  = 0.0; _calibAz  = 0.0
        active    = true
    }

    function stop() { active = false }

    // advance(): avanza la posición DR con el heading IMU actual y la velocidad dada.
    // Llamar desde _drSimulateTick en cada tick DR real (no interpolado).
    function advance(speedMs, dt) {
        if (!calibrated || speedMs < 0.05 || dt <= 0.0 || dt > 1.0) return
        var R   = 6371000.0
        var hdg = headingRad
        var dlat = speedMs * dt * Math.cos(hdg) / R * (180.0 / Math.PI)
        var dlon = speedMs * dt * Math.sin(hdg) / (R * Math.cos(imuLat * Math.PI / 180.0)) * (180.0 / Math.PI)
        imuLat += dlat
        imuLon += dlon
    }

    // ── Parámetros del filtro ────────────────────────────────────────────────
    readonly property int  calibN:  80      // muestras accel para calibrar (~1.6 s a 50 Hz)
    readonly property real mahonyKp: 2.0    // ganancia proporcional Mahony
    readonly property real mahonyKi: 0.005  // ganancia integral Mahony

    // gyroScale y yawSign se auto-detectan con feedGpsHeading() durante marcha normal.
    // Valores iniciales seguros; sobrescritos en cuanto hay suficientes datos GPS.
    //   gyroScale: 1.0 = rad/s (Android HAL / Ubuntu Touch)
    //              Math.PI/180 = deg/s (QtSensors desktop estándar)
    //   yawSign:   +1 si girar a la derecha incrementa headingRad; −1 en caso contrario.
    property real gyroScale:  1.0
    property real yawSign:    1.0

    // Persiste la calibración GPS (gyroScale/yawSign) entre reinicios: sin esto,
    // cada arranque parte de valores por defecto y hay que recalibrar girando con
    // GPS bueno antes de que el DR por IMU sea fiable en el próximo túnel.
    Settings {
        category: "imu"
        property alias gyroScale:          root.gyroScale
        property alias yawSign:             root.yawSign
        property alias gpsScaleCalibrated: root.gpsScaleCalibrated
    }

    // ── Debug / diagnóstico ───────────────────────────────────────────────────
    // rawGz: último valor crudo del eje Z del giroscopio (unidades del sensor).
    // Observar en reposo (≈0) y al girar lentamente (~1 rad/s o ~57 deg/s).
    // Si rawGz ≈ 1 al girar 1 rad/s → gyroScale=1.0. Si ≈57 → gyroScale=Math.PI/180.
    property real rawGz:         0.0
    property real yawDeltaDeg:   0.0    // Δheading acumulado desde start(), en grados (más legible)
    property real accelMag:      0.0    // |acelerómetro| en m/s² (en reposo ≈ 9.8)

    // ── Auto-calibración con GPS ──────────────────────────────────────────────
    // Llamar feedGpsHeading(hdgRad) en cada tick GPS bueno mientras el vehículo gira.
    // Tras gpsCalibN muestras válidas, gyroScale y yawSign quedan fijados automáticamente.
    readonly property int  gpsCalibTarget:    20    // muestras para estimar la escala
    readonly property real gpsCalibMinDh:   0.05  // rad mínimo de cambio entre muestras
    property bool   gpsScaleCalibrated: false
    property real   _gpsHdgPrev:        -999.0
    property real   _gpsYawAccum:       0.0     // Σ Δheading GPS (rad)
    property real   _imuYawAccum:       0.0     // Σ Δheading IMU sin escalar (rad)
    property int    _gpsCalibN:         0

    // Llamar desde GpsSource en cada tick GPS real bueno (fuera de DR) para auto-calibrar.
    // hdgRad: heading GPS del tick actual.
    function feedGpsHeading(hdgRad) {
        if (gpsScaleCalibrated || !calibrated) return

        if (_gpsHdgPrev < -998.0) { _gpsHdgPrev = hdgRad; return }

        // Δheading GPS entre ticks consecutivos (corregido por wrap-around)
        var dGps = hdgRad - _gpsHdgPrev
        while (dGps >  Math.PI) dGps -= 2*Math.PI
        while (dGps < -Math.PI) dGps += 2*Math.PI
        _gpsHdgPrev = hdgRad

        // Solo acumular si hay un giro perceptible (evita ruido en línea recta)
        if (Math.abs(dGps) < gpsCalibMinDh) return

        _gpsYawAccum += dGps
        _imuYawAccum += _rawGzAccum    // Σ(gzRaw·dt) en unidades del sensor
        _rawGzAccum   = 0.0
        _gpsCalibN++

        if (_gpsCalibN >= gpsCalibTarget && Math.abs(_imuYawAccum) > 0.01) {
            // Ratio GPS/IMU → escala correcta para gyroScale
            var ratio = _gpsYawAccum / _imuYawAccum
            gyroScale = gyroScale * Math.abs(ratio)   // ajustar escala
            yawSign   = ratio > 0 ? 1.0 : -1.0        // ajustar signo
            gpsScaleCalibrated = true
            console.log("[NavImu] GPS calib: gyroScale=", gyroScale.toFixed(5),
                        " yawSign=", yawSign, " tras", _gpsCalibN, "muestras")
        }
    }

    // Resetea los acumuladores de calibración GPS (útil al cambiar de vehículo/orientación)
    function resetGpsCalib() {
        gpsScaleCalibrated = false
        _gpsHdgPrev  = -999.0
        _gpsYawAccum = 0.0
        _imuYawAccum = 0.0
        _rawGzAccum  = 0.0
        _gpsCalibN   = 0
    }

    // Integral cruda de gzRaw×dt desde el último feedGpsHeading(): Σ(gzRaw·dt).
    // En unidades del sensor × s (rad si rad/s, grados si deg/s).
    // La ratio GPS/IMU da la escala correcta para gyroScale.
    property real _rawGzAccum: 0.0

    // ── Estado interno ───────────────────────────────────────────────────────
    property var  _q:      [1.0, 0.0, 0.0, 0.0]   // cuaternión actitud [w,x,y,z]
    property var  _eInt:   [0.0, 0.0, 0.0]         // integral del error Mahony
    property real _yaw0:   0.0                      // heading GPS al inicio

    // Timestamp de la última lectura del giroscopio (ms; −1 = no inicializado)
    property real _lastTs: -1.0

    // Última lectura del acelerómetro (m/s²), actualizada en cada callback
    property real _lastAx: 0.0
    property real _lastAy: 0.0
    property real _lastAz: 9.8

    // Acumuladores de calibración
    property int  _calibN:  0
    property real _calibAx: 0.0
    property real _calibAy: 0.0
    property real _calibAz: 0.0

    // ── Sensores ─────────────────────────────────────────────────────────────
    Accelerometer {
        id: accelSensor
        active:   root.active || root.gpsActive
        dataRate: 50
        onReadingChanged: root._onAccelReading(reading.x, reading.y, reading.z, reading.timestamp)
    }

    Gyroscope {
        id: gyroSensor
        active:   root.active || root.gpsActive
        dataRate: 50
        onReadingChanged: root._onGyroReading(reading.x, reading.y, reading.z, reading.timestamp)
    }

    // ── Callbacks de sensor ──────────────────────────────────────────────────

    function _onAccelReading(ax, ay, az, ts) {
        _lastAx = ax; _lastAy = ay; _lastAz = az
        accelMag = Math.sqrt(ax*ax + ay*ay + az*az)
        if (calibrated) return

        // Fase de calibración: promediar lecturas en reposo para fijar vector gravedad inicial.
        // El filtro Mahony usará el acelerómetro dinámicamente para corregir la inclinación,
        // pero la calibración sirve como punto de referencia del estado [1,0,0,0].
        _calibAx += ax; _calibAy += ay; _calibAz += az
        _calibN++
        calibProgress = Math.min(1.0, _calibN / calibN)
        if (_calibN >= calibN) calibrated = true
    }

    function _onGyroReading(gxRaw, gyRaw, gzRaw, ts) {
        rawGz = gzRaw   // exponer valor crudo para diagnóstico

        // ts en µs; convertir a ms para dt en segundos
        var tsMs = (ts > 0) ? ts / 1000.0 : Date.now()
        var dt   = (_lastTs >= 0) ? (tsMs - _lastTs) / 1000.0 : 0.0
        _lastTs  = tsMs
        if (!calibrated || dt <= 0.0 || dt > 0.5) return

        var gx = gxRaw * gyroScale
        var gy = gyRaw * gyroScale
        var gz = gzRaw * gyroScale

        // ── Corrección Mahony ─────────────────────────────────────────────────
        // Normalizar lectura del acelerómetro (gravedad medida en frame dispositivo)
        var ax = _lastAx, ay = _lastAy, az = _lastAz
        var alen = Math.sqrt(ax*ax + ay*ay + az*az)
        if (alen > 0.1) {
            ax /= alen; ay /= alen; az /= alen

            // Gravedad estimada en frame dispositivo a partir del cuaternión actual.
            // Corresponde al eje Z del mundo (arriba) rotado al frame del dispositivo:
            //   v = q^{-1} · [0,0,1] · q
            var qw=_q[0], qx=_q[1], qy=_q[2], qz=_q[3]
            var vx =  2.0*(qx*qz - qw*qy)
            var vy =  2.0*(qy*qz + qw*qx)
            var vz =  qw*qw - qx*qx - qy*qy + qz*qz

            // Error = cross(gravedad_medida, gravedad_estimada)
            // Un error no nulo indica que el cuaternión está mal alineado con la gravedad.
            var ex = ay*vz - az*vy
            var ey = az*vx - ax*vz
            var ez = ax*vy - ay*vx

            // Acumular integral del error (reduce deriva lenta del giroscopio)
            _eInt = [_eInt[0] + ex*dt, _eInt[1] + ey*dt, _eInt[2] + ez*dt]

            // Aplicar feedback proporcional + integral al giroscopio corregido
            gx += mahonyKp*ex + mahonyKi*_eInt[0]
            gy += mahonyKp*ey + mahonyKi*_eInt[1]
            gz += mahonyKp*ez + mahonyKi*_eInt[2]
        }

        // ── Integración del cuaternión ────────────────────────────────────────
        // Aproximación de ángulo pequeño: dq ≈ [1, ω·dt/2] para |ω·dt| << 1
        var h = dt * 0.5
        _q = _qNorm(_qMul(_q, [1.0, gx*h, gy*h, gz*h]))

        // ── Extracción de yaw (rotación alrededor del eje Z del mundo) ─────────
        // Ángulo de Euler yaw en convenio ZYX a partir del cuaternión:
        //   yaw = atan2(2(qw·qz + qx·qy),  1 − 2(qy² + qz²))
        // Este yaw es relativo al frame inicial (q=[1,0,0,0] → yaw=0),
        // por lo que representa el ΔyawDesde activación.
        // Acumular integral cruda (sin escala) para auto-calibración GPS
        _rawGzAccum += gzRaw * dt

        var q = _q
        var yawDelta = Math.atan2(2.0*(q[0]*q[3] + q[1]*q[2]),
                                  1.0 - 2.0*(q[2]*q[2] + q[3]*q[3]))
        yawDeltaDeg = yawDelta * yawSign * (180.0 / Math.PI)
        headingRad  = _normAngle(_yaw0 + yawSign * yawDelta)
    }

    // ── Aritmética de cuaterniones ───────────────────────────────────────────

    // Producto de cuaterniones Hamilton: a ⊗ b
    function _qMul(a, b) {
        return [
            a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3],
            a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2],
            a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1],
            a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0]
        ]
    }

    // Normalización del cuaternión (mantiene |q|=1 para evitar deriva numérica)
    function _qNorm(q) {
        var n = Math.sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
        return n > 1e-10 ? [q[0]/n, q[1]/n, q[2]/n, q[3]/n] : [1.0, 0.0, 0.0, 0.0]
    }

    function _normAngle(a) {
        while (a >  Math.PI) a -= 2.0 * Math.PI
        while (a < -Math.PI) a += 2.0 * Math.PI
        return a
    }
}
