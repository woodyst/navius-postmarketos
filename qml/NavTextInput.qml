import QtQuick 2.7

// Sustituto de TextInput que muestra/oculta el teclado en pantalla al entrar
// y salir del campo. Phosh (phosh-osk-stevia) no implementa el protocolo
// estándar Wayland text-input-v3 ni ninguna integración con Qt5 (solo GTK,
// vía un módulo propio de Phosh) — Qt.inputMethod.show()/hide() nunca hace
// nada en este dispositivo. Se llama en su lugar a la API D-Bus propia de
// Phosh (sm.puri.OSK0.SetVisible, ver src/nav_osk.rs) directamente desde
// aquí. (El truco de sombrear "TextInput.qml" por prioridad de directorio no
// funciona con los recursos qrc embebidos — de ahí el nombre explícito y la
// sustitución mecánica de los sitios de uso.)
TextInput {
    id: root
    onActiveFocusChanged: {
        if (readOnly) return
        if (typeof navOsk !== "undefined" && navOsk) navOsk.set_visible(activeFocus)
    }
}
