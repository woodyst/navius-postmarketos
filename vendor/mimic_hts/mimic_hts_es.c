/*
 * mimic_hts_es — TTS español con Mimic1 + motor HTS
 *
 * Usa:
 *   - cmu_grapheme_lang: frontend de lenguaje para español (tokenización)
 *   - es_hts_g2p:        G2P español propio (grafemas→fonemas HTS)
 *   - hts_synth:         síntesis por modelos HMM
 *   - cstr_upc_upm_spanish_hts.htsvoice: voz española de la UPC/UPM
 *
 * Uso:
 *   ./mimic_hts_es "Texto" [salida.wav] [ruta/voz.htsvoice]
 */

#include <stdio.h>
#include <stdlib.h>
#include "mimic.h"
#include "cmu_grapheme_lang.h"
#include "flite_hts_engine.h"

extern cst_lexicon *es_hts_lex_init(void);
extern cst_val     *es_hts_tokentowords(cst_item *token);
extern cst_utterance *hts_synth(cst_utterance *utt);

static cst_voice *make_hts_es_voice(const char *htsvoice_path)
{
    cst_voice *vox = new_voice();
    cst_lexicon *lex;
    Flite_HTS_Engine *flite_hts;

    vox->name = "hts_es";

    /* Frontend grapheme: tokenización + sobrescribir expansión numérica en español */
    cmu_grapheme_lang_init(vox);
    mimic_feat_set(vox->features, "tokentowords_func", itemfunc_val(es_hts_tokentowords));

    lex = es_hts_lex_init();
    mimic_feat_set(vox->features, "lexicon", lexicon_val(lex));
    if (lex->postlex)
        mimic_feat_set(vox->features, "postlex_func", uttfunc_val(lex->postlex));

    mimic_feat_set_string(vox->features, "name", "hts_es");

    /* El motor HTS gestiona duración y f0 internamente */
    mimic_feat_set_string(vox->features, "no_segment_duration_model", "1");
    mimic_feat_set_string(vox->features, "no_f0_target_model", "1");

    /* Motor HTS */
    flite_hts = cst_alloc(Flite_HTS_Engine, 1);
    Flite_HTS_Engine_initialize(flite_hts);
    mimic_feat_set_string(vox->features, "htsvoice_file", htsvoice_path);
    mimic_feat_set(vox->features, "flite_hts", flitehtsengine_val(flite_hts));

    /* Síntesis HMM */
    mimic_feat_set(vox->features, "wave_synth_func", uttfunc_val(&hts_synth));
    mimic_feat_set_int(vox->features, "sample_rate",
                       Flite_HTS_Engine_get_sampling_frequency(flite_hts));

    return vox;
}

int main(int argc, char *argv[])
{
    const char *text        = "Hola, soy el motor mimic con voz HTS española";
    const char *outfile     = "output_hts.wav";
    const char *htsvoice    = "hts_voices/cstr_upc_upm_spanish_hts.htsvoice";

    if (argc > 1) text      = argv[1];
    if (argc > 2) outfile   = argv[2];
    if (argc > 3) htsvoice  = argv[3];

    mimic_init();

    cst_voice *vox  = make_hts_es_voice(htsvoice);
    cst_wave  *wave = mimic_text_to_wave(text, vox);

    if (!wave) {
        fprintf(stderr, "ERROR: síntesis fallida\n");
        return 1;
    }

    cst_wave_save_riff(wave, outfile);
    printf("WAV guardado: %s\n", outfile);

    delete_wave(wave);
    delete_voice(vox);
    return 0;
}
