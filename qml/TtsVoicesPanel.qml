import QtQuick 2.7
import QtQuick.Controls 2.15

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 310
    color: "#0D1117"

    // ── API ──────────────────────────────────────────────────────────────────
    property var ttsRef    // navTts QObject

    signal closed()

    function open() {
        visible = true
        _refresh()
    }
    function close() {
        visible = false
        closed()
    }

    // ── Voice catalogues per language (rhasspy/piper-voices v1.0.0) ──────────
    readonly property var _esVoices: [
        { lang: "es_AR-daniela-high",    label: "es_AR-daniela",    quality: "high",   sizeMb: 109, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_AR/daniela/high/es_AR-daniela-high.onnx" },
        { lang: "es_ES-carlfm-x_low",    label: "es_ES-carlfm",     quality: "x_low",  sizeMb: 27,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/carlfm/x_low/es_ES-carlfm-x_low.onnx" },
        { lang: "es_ES-davefx-medium",   label: "es_ES-davefx",     quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx" },
        { lang: "es_ES-mls_10246-low",   label: "es_ES-mls_10246",  quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_10246/low/es_ES-mls_10246-low.onnx" },
        { lang: "es_ES-mls_9972-low",    label: "es_ES-mls_9972",   quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_9972/low/es_ES-mls_9972-low.onnx" },
        { lang: "es_ES-sharvard-medium", label: "es_ES-sharvard",   quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx" },
        { lang: "es_MX-ald-medium",      label: "es_MX-ald",        quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_MX/ald/medium/es_MX-ald-medium.onnx" },
        { lang: "es_MX-claude-high",     label: "es_MX-claude",     quality: "high",   sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_MX/claude/high/es_MX-claude-high.onnx" }
    ]
    readonly property var _enVoices: [
        { lang: "en_GB-alan-low",                    label: "en_GB-alan",                   quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alan/low/en_GB-alan-low.onnx" },
        { lang: "en_GB-alan-medium",                 label: "en_GB-alan",                   quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alan/medium/en_GB-alan-medium.onnx" },
        { lang: "en_GB-alba-medium",                 label: "en_GB-alba",                   quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alba/medium/en_GB-alba-medium.onnx" },
        { lang: "en_GB-aru-medium",                  label: "en_GB-aru",                    quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/aru/medium/en_GB-aru-medium.onnx" },
        { lang: "en_GB-cori-medium",                 label: "en_GB-cori",                   quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/cori/medium/en_GB-cori-medium.onnx" },
        { lang: "en_GB-cori-high",                   label: "en_GB-cori",                   quality: "high",   sizeMb: 109, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/cori/high/en_GB-cori-high.onnx" },
        { lang: "en_GB-jenny_dioco-medium",          label: "en_GB-jenny_dioco",             quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx" },
        { lang: "en_GB-northern_english_male-medium",label: "en_GB-northern_english_male",   quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/northern_english_male/medium/en_GB-northern_english_male-medium.onnx" },
        { lang: "en_GB-semaine-medium",              label: "en_GB-semaine",                quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/semaine/medium/en_GB-semaine-medium.onnx" },
        { lang: "en_GB-southern_english_female-low", label: "en_GB-southern_english_female", quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/southern_english_female/low/en_GB-southern_english_female-low.onnx" },
        { lang: "en_GB-vctk-medium",                 label: "en_GB-vctk",                   quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/vctk/medium/en_GB-vctk-medium.onnx" },
        { lang: "en_US-amy-low",                     label: "en_US-amy",                    quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx" },
        { lang: "en_US-amy-medium",                  label: "en_US-amy",                    quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx" },
        { lang: "en_US-arctic-medium",               label: "en_US-arctic",                 quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/arctic/medium/en_US-arctic-medium.onnx" },
        { lang: "en_US-bryce-medium",                label: "en_US-bryce",                  quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/bryce/medium/en_US-bryce-medium.onnx" },
        { lang: "en_US-danny-low",                   label: "en_US-danny",                  quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/danny/low/en_US-danny-low.onnx" },
        { lang: "en_US-hfc_female-medium",           label: "en_US-hfc_female",             quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_female/medium/en_US-hfc_female-medium.onnx" },
        { lang: "en_US-hfc_male-medium",             label: "en_US-hfc_male",               quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/hfc_male/medium/en_US-hfc_male-medium.onnx" },
        { lang: "en_US-joe-medium",                  label: "en_US-joe",                    quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/joe/medium/en_US-joe-medium.onnx" },
        { lang: "en_US-john-medium",                 label: "en_US-john",                   quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/john/medium/en_US-john-medium.onnx" },
        { lang: "en_US-kathleen-low",                label: "en_US-kathleen",               quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kathleen/low/en_US-kathleen-low.onnx" },
        { lang: "en_US-kristin-medium",              label: "en_US-kristin",                quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kristin/medium/en_US-kristin-medium.onnx" },
        { lang: "en_US-kusal-medium",                label: "en_US-kusal",                  quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/kusal/medium/en_US-kusal-medium.onnx" },
        { lang: "en_US-l2arctic-medium",             label: "en_US-l2arctic",               quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/l2arctic/medium/en_US-l2arctic-medium.onnx" },
        { lang: "en_US-lessac-low",                  label: "en_US-lessac",                 quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/low/en_US-lessac-low.onnx" },
        { lang: "en_US-lessac-medium",               label: "en_US-lessac",                 quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx" },
        { lang: "en_US-lessac-high",                 label: "en_US-lessac",                 quality: "high",   sizeMb: 109, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/high/en_US-lessac-high.onnx" },
        { lang: "en_US-libritts_r-medium",           label: "en_US-libritts_r",             quality: "medium", sizeMb: 75,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/libritts_r/medium/en_US-libritts_r-medium.onnx" },
        { lang: "en_US-libritts-high",               label: "en_US-libritts",               quality: "high",   sizeMb: 130, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/libritts/high/en_US-libritts-high.onnx" },
        { lang: "en_US-ljspeech-medium",             label: "en_US-ljspeech",               quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/medium/en_US-ljspeech-medium.onnx" },
        { lang: "en_US-ljspeech-high",               label: "en_US-ljspeech",               quality: "high",   sizeMb: 109, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ljspeech/high/en_US-ljspeech-high.onnx" },
        { lang: "en_US-norman-medium",               label: "en_US-norman",                 quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/norman/medium/en_US-norman-medium.onnx" },
        { lang: "en_US-reza_ibrahim-medium",         label: "en_US-reza_ibrahim",           quality: "medium", sizeMb: 61,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/reza_ibrahim/medium/en_US-reza_ibrahim-medium.onnx" },
        { lang: "en_US-ryan-low",                    label: "en_US-ryan",                   quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/low/en_US-ryan-low.onnx" },
        { lang: "en_US-ryan-medium",                 label: "en_US-ryan",                   quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/medium/en_US-ryan-medium.onnx" },
        { lang: "en_US-ryan-high",                   label: "en_US-ryan",                   quality: "high",   sizeMb: 115, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/high/en_US-ryan-high.onnx" },
        { lang: "en_US-sam-medium",                  label: "en_US-sam",                    quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/sam/medium/en_US-sam-medium.onnx" }
    ]
    readonly property var _frVoices: [
        { lang: "fr_FR-gilles-low",     label: "fr_FR-gilles",    quality: "low",    sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/gilles/low/fr_FR-gilles-low.onnx" },
        { lang: "fr_FR-mls-medium",     label: "fr_FR-mls",       quality: "medium", sizeMb: 73, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/mls/medium/fr_FR-mls-medium.onnx" },
        { lang: "fr_FR-mls_1840-low",   label: "fr_FR-mls_1840",  quality: "low",    sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/mls_1840/low/fr_FR-mls_1840-low.onnx" },
        { lang: "fr_FR-siwis-low",      label: "fr_FR-siwis",     quality: "low",    sizeMb: 27, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/siwis/low/fr_FR-siwis-low.onnx" },
        { lang: "fr_FR-siwis-medium",   label: "fr_FR-siwis",     quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx" },
        { lang: "fr_FR-tom-medium",     label: "fr_FR-tom",       quality: "medium", sizeMb: 61, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/tom/medium/fr_FR-tom-medium.onnx" },
        { lang: "fr_FR-upmc-medium",    label: "fr_FR-upmc",      quality: "medium", sizeMb: 73, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/fr/fr_FR/upmc/medium/fr_FR-upmc-medium.onnx" }
    ]
    readonly property var _deVoices: [
        { lang: "de_DE-eva_k-x_low",            label: "de_DE-eva_k",            quality: "x_low",  sizeMb: 20,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx" },
        { lang: "de_DE-karlsson-low",            label: "de_DE-karlsson",         quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/karlsson/low/de_DE-karlsson-low.onnx" },
        { lang: "de_DE-kerstin-low",             label: "de_DE-kerstin",          quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/kerstin/low/de_DE-kerstin-low.onnx" },
        { lang: "de_DE-mls-medium",              label: "de_DE-mls",              quality: "medium", sizeMb: 73,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/mls/medium/de_DE-mls-medium.onnx" },
        { lang: "de_DE-pavoque-low",             label: "de_DE-pavoque",          quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/pavoque/low/de_DE-pavoque-low.onnx" },
        { lang: "de_DE-ramona-low",              label: "de_DE-ramona",           quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/ramona/low/de_DE-ramona-low.onnx" },
        { lang: "de_DE-thorsten-low",            label: "de_DE-thorsten",         quality: "low",    sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/low/de_DE-thorsten-low.onnx" },
        { lang: "de_DE-thorsten-medium",         label: "de_DE-thorsten",         quality: "medium", sizeMb: 60,  url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx" },
        { lang: "de_DE-thorsten-high",           label: "de_DE-thorsten",         quality: "high",   sizeMb: 109, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx" },
        { lang: "de_DE-thorsten_emotional-medium",label: "de_DE-thorsten_emotional",quality: "medium",sizeMb: 73, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx" }
    ]
    readonly property var _ptVoices: [
        { lang: "pt_BR-cadu-medium",    label: "pt_BR-cadu",    quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/cadu/medium/pt_BR-cadu-medium.onnx" },
        { lang: "pt_BR-edresson-low",   label: "pt_BR-edresson",quality: "low",    sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/edresson/low/pt_BR-edresson-low.onnx" },
        { lang: "pt_BR-faber-medium",   label: "pt_BR-faber",   quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx" },
        { lang: "pt_BR-jeff-medium",    label: "pt_BR-jeff",    quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_BR/jeff/medium/pt_BR-jeff-medium.onnx" },
        { lang: "pt_PT-tugão-medium",   label: "pt_PT-tugão",   quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pt/pt_PT/tug%C3%A3o/medium/pt_PT-tug%C3%A3o-medium.onnx" }
    ]
    readonly property var _itVoices: [
        { lang: "it_IT-paola-medium",   label: "it_IT-paola",   quality: "medium", sizeMb: 61, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/it/it_IT/paola/medium/it_IT-paola-medium.onnx" },
        { lang: "it_IT-riccardo-x_low", label: "it_IT-riccardo",quality: "x_low",  sizeMb: 27, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/it/it_IT/riccardo/x_low/it_IT-riccardo-x_low.onnx" }
    ]
    readonly property var _caVoices: [
        { lang: "ca_ES-upc_ona-x_low",  label: "ca_ES-upc_ona", quality: "x_low",  sizeMb: 20, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_ona/x_low/ca_ES-upc_ona-x_low.onnx" },
        { lang: "ca_ES-upc_ona-medium",  label: "ca_ES-upc_ona", quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_ona/medium/ca_ES-upc_ona-medium.onnx" },
        { lang: "ca_ES-upc_pau-x_low",   label: "ca_ES-upc_pau", quality: "x_low",  sizeMb: 27, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ca/ca_ES/upc_pau/x_low/ca_ES-upc_pau-x_low.onnx" }
    ]
    readonly property var _ruVoices: [
        { lang: "ru_RU-ru_demo-medium",        label: "ru_RU-ru_demo",        quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/ru_demo/medium/ru_RU-ru_demo-medium.onnx" },
        { lang: "ru_RU-ru_glas_female-medium", label: "ru_RU-ru_glas_female", quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/ru_glas_female/medium/ru_RU-ru_glas_female-medium.onnx" },
        { lang: "ru_RU-ru_glas_male-medium",   label: "ru_RU-ru_glas_male",   quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU/ru_glas_male/medium/ru_RU-ru_glas_male-medium.onnx" }
    ]
    readonly property var _zhVoices: [
        { lang: "zh_CN-huayan-x_low",  label: "zh_CN-huayan", quality: "x_low",  sizeMb: 20, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/zh/zh_CN/huayan/x_low/zh_CN-huayan-x_low.onnx" },
        { lang: "zh_CN-huayan-medium", label: "zh_CN-huayan", quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx" }
    ]
    readonly property var _arVoices: [
        { lang: "ar_JO-kareem-low",    label: "ar_JO-kareem", quality: "low",    sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/low/ar_JO-kareem-low.onnx" },
        { lang: "ar_JO-kareem-medium", label: "ar_JO-kareem", quality: "medium", sizeMb: 60, url: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx" }
    ]

    // ── Per-voice status ──────────────────────────────────────────────────────
    property var _st: ({})

    function _refresh() {
        var s = {}
        var groups = [_esVoices, _enVoices, _frVoices, _deVoices, _ptVoices,
                      _itVoices, _caVoices, _ruVoices, _zhVoices, _arVoices]
        for (var g = 0; g < groups.length; g++) {
            for (var i = 0; i < groups[g].length; i++) {
                var id = groups[g][i].lang
                s[id] = panel.ttsRef ? panel.ttsRef.download_status(id) : "idle"
            }
        }
        _st = s
    }

    function _stOf(voiceId) { return _st[voiceId] || "idle" }

    Timer {
        interval: 2000
        running: panel.visible
        repeat: true
        onTriggered: panel._refresh()
    }

    // ── Shared voice card delegate ────────────────────────────────────────────
    Component {
        id: voiceCard
        Column {
            id: delegateRoot
            width: col.width; spacing: 0

            property string st:  panel._stOf(modelData.lang)
            property bool ins:   st === "installed"
            property bool dling: st.indexOf("downloading") === 0
            property bool err:   st.indexOf("error") === 0
            property int  dlB:   dling ? (parseInt(st.split(":")[1]) || 0) : 0

            Rectangle {
                anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                height: cardCol.implicitHeight + units.gu(3)
                color: "#1C1C2E"; radius: units.gu(1)

                Column {
                    id: cardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1.5) }
                    spacing: units.gu(0.8)

                    Row {
                        spacing: units.gu(1)
                        Label {
                            text: modelData.label
                            color: "white"; font.pixelSize: ts(1.85); font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            height: units.gu(2.4); radius: height/2
                            width: qLbl.implicitWidth + units.gu(1.5)
                            color: modelData.quality === "high"  ? "#4A148C" :
                                   modelData.quality === "medium"? "#1A237E" :
                                   modelData.quality === "low"   ? "#1B3A1B" : "#2A2A2A"
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                id: qLbl; anchors.centerIn: parent
                                text: modelData.quality
                                color: modelData.quality === "high"  ? "#CE93D8" :
                                       modelData.quality === "medium"? "#90CAF9" :
                                       modelData.quality === "low"   ? "#A5D6A7" : "#78909C"
                                font.pixelSize: ts(1.5)
                            }
                        }
                        Label {
                            text: modelData.sizeMb + " MB"
                            color: "#90A4AE"; font.pixelSize: ts(1.55)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Progress bar
                    Rectangle {
                        visible: delegateRoot.dling
                        width: parent.width; height: units.gu(0.6); radius: height/2
                        color: "#2A2A3E"
                        Rectangle {
                            width: Math.min(parent.width,
                                   parent.width * delegateRoot.dlB / (modelData.sizeMb * 1024 * 1024))
                            height: parent.height; radius: parent.radius; color: "#29B6F6"
                            Behavior on width { NumberAnimation { duration: 500 } }
                        }
                    }

                    // Status + buttons
                    Row {
                        spacing: units.gu(0.8)

                        Rectangle {
                            height: units.gu(3.2); radius: height/2
                            width: stLbl.implicitWidth + units.gu(2)
                            color: delegateRoot.ins   ? "#1B5E20" :
                                   delegateRoot.dling ? "#1A237E" :
                                   delegateRoot.err   ? "#7F1010" : "#2A2A3E"
                            Label {
                                id: stLbl; anchors.centerIn: parent
                                text: delegateRoot.ins   ? i18n.tr("✓ Instalada") :
                                      delegateRoot.dling ? ("↓ " + Math.round(delegateRoot.dlB/1048576) + "/" + modelData.sizeMb + " MB") :
                                      delegateRoot.err   ? i18n.tr("Error") : i18n.tr("No instalada")
                                color: delegateRoot.ins ? "#4CAF50" : delegateRoot.dling ? "#29B6F6" : delegateRoot.err ? "#EF5350" : "#546E7A"
                                font.pixelSize: ts(1.6)
                            }
                        }

                        Rectangle {
                            visible: !delegateRoot.ins && !delegateRoot.dling
                            height: units.gu(3.2); radius: height/2; width: units.gu(12)
                            color: "#1565C3"
                            Label { anchors.centerIn: parent; text: i18n.tr("Descargar"); color: "white"; font.pixelSize: ts(1.6) }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    panel.ttsRef.download_voice(modelData.lang, modelData.url)
                                    var s = panel._st
                                    s[modelData.lang] = "downloading:0"
                                    panel._st = s
                                }
                            }
                        }

                        Rectangle {
                            visible: delegateRoot.ins
                            height: units.gu(3.2); radius: height/2; width: units.gu(12)
                            color: "#7F1010"
                            Label { anchors.centerIn: parent; text: i18n.tr("Desinstalar"); color: "white"; font.pixelSize: ts(1.6) }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    panel.ttsRef.delete_voice(modelData.lang)
                                    panel._refresh()
                                }
                            }
                        }
                    }
                }
            }
            Item { width: 1; height: units.gu(1.2) }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    Rectangle {
        id: hdr
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(7); color: "#161B22"
        Label {
            anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
            text: i18n.tr("Voces TTS"); color: "white"; font.pixelSize: ts(2.2); font.bold: true
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: units.gu(1.5); verticalCenter: parent.verticalCenter }
            width: units.gu(6); height: units.gu(6); radius: width/2; color: "#29B6F6"
            Label { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: ts(2.2) }
            MouseArea { anchors.fill: parent; onClicked: panel.close() }
        }
    }

    // ── Content ───────────────────────────────────────────────────────────────
    Flickable {
        anchors { top: hdr.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: 0

            Item { width: 1; height: units.gu(2) }

            // ── espeak-ng ─────────────────────────────────────────────────────
            Label {
                x: units.gu(2.5)
                text: "espeak-ng · " + i18n.tr("Motor de reserva")
                color: "#B0BEC5"; font.pixelSize: ts(1.8)
            }
            Item { width: 1; height: units.gu(0.8) }

            Rectangle {
                anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                height: espeakCol.implicitHeight + units.gu(3)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: espeakCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1.5) }
                    spacing: units.gu(0.6)
                    Label {
                        text: "ar · ca · de · en · es · fa · fr · it · pt · ru · zh · y otros"
                        color: "white"; font.pixelSize: ts(1.9)
                        wrapMode: Text.Wrap; width: parent.width
                    }
                    Label {
                        text: i18n.tr("✓ Siempre disponible — integrado en la app")
                        color: "#4CAF50"; font.pixelSize: ts(1.6)
                    }
                }
            }

            Item { width: 1; height: units.gu(2) }

            // ── PicoTTS ───────────────────────────────────────────────────────
            Label {
                x: units.gu(2.5)
                text: "PicoTTS · " + i18n.tr("Calidad media")
                color: "#B0BEC5"; font.pixelSize: ts(1.8)
            }
            Item { width: 1; height: units.gu(0.8) }

            Rectangle {
                anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                height: picoCol.implicitHeight + units.gu(3)
                color: "#1C1C2E"; radius: units.gu(1)
                Column {
                    id: picoCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1.5) }
                    spacing: units.gu(0.6)
                    Label { text: "de · en-US · en-GB · es · fr · it"; color: "white"; font.pixelSize: ts(1.9) }
                    Label {
                        text: panel.ttsRef && panel.ttsRef.engine_available("picotts")
                              ? i18n.tr("✓ Disponible")
                              : i18n.tr("Pendiente de compilar (clickable build)")
                        color: panel.ttsRef && panel.ttsRef.engine_available("picotts") ? "#4CAF50" : "#FF8F00"
                        font.pixelSize: ts(1.6)
                    }
                }
            }

            Item { width: 1; height: units.gu(2) }

            // ── Piper ─────────────────────────────────────────────────────────
            Label {
                x: units.gu(2.5)
                text: "Piper · " + i18n.tr("Alta calidad (neuronal)")
                color: "#B0BEC5"; font.pixelSize: ts(1.8)
            }
            Item { width: 1; height: units.gu(0.5) }

            // Español
            Label { x: units.gu(3); text: "🇪🇸  Español"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._esVoices; delegate: voiceCard }

            // English
            Label { x: units.gu(3); text: "🇬🇧🇺🇸  English"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._enVoices; delegate: voiceCard }

            // Français
            Label { x: units.gu(3); text: "🇫🇷  Français"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._frVoices; delegate: voiceCard }

            // Deutsch
            Label { x: units.gu(3); text: "🇩🇪  Deutsch"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._deVoices; delegate: voiceCard }

            // Português
            Label { x: units.gu(3); text: "🇧🇷🇵🇹  Português"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._ptVoices; delegate: voiceCard }

            // Italiano
            Label { x: units.gu(3); text: "🇮🇹  Italiano"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._itVoices; delegate: voiceCard }

            // Català
            Label { x: units.gu(3); text: "🏴  Català"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._caVoices; delegate: voiceCard }

            // Русский
            Label { x: units.gu(3); text: "🇷🇺  Русский"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._ruVoices; delegate: voiceCard }

            // 中文
            Label { x: units.gu(3); text: "🇨🇳  中文"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._zhVoices; delegate: voiceCard }

            // العربية
            Label { x: units.gu(3); text: "🇯🇴  العربية"; color: "#90A4AE"; font.pixelSize: ts(1.65) }
            Item { width: 1; height: units.gu(0.5) }
            Repeater { model: panel._arVoices; delegate: voiceCard }

            Item { width: 1; height: units.gu(3) }
        }
    }
}
