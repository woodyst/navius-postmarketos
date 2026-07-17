/*
 * es_hts_g2p.c — Spanish G2P for Mimic1 HTS voice (UPC/UPM phoneme set)
 *
 * Phoneme set: a a1 e e1 i i0 i1 o o1 u u0 u1
 *              p t k b d g f s x th m n ny l ll r rr ch pau
 *
 * Rules: Castilian Spanish (c/z → th, ll ≠ y)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "mimic.h"
#include "cst_val.h"
#include "cst_lexicon.h"
#include "cst_item.h"
#include "cst_utterance.h"

/* ------------------------------------------------------------------ */
/* Simple dynamic array of phoneme strings                             */
/* ------------------------------------------------------------------ */
#define PB_MAX 128
typedef struct { const char *p[PB_MAX]; int n; } PhBuf;

static void pb_push(PhBuf *pb, const char *ph)
{
    if (pb->n < PB_MAX)
        pb->p[pb->n++] = ph;
}

/* ------------------------------------------------------------------ */
/* UTF-8 helpers for Spanish characters                               */
/* ------------------------------------------------------------------ */

/* Decode accented vowel at position i; returns base vowel char (a/e/i/o/u),
   sets *stressed=1 if accented, *len to bytes consumed. Returns 0 if not a vowel. */
static char decode_vowel(const unsigned char *s, int i, int *stressed, int *len)
{
    unsigned char b0 = s[i], b1 = s[i+1];
    *stressed = 0;
    *len = 1;

    if (b0 == 0xC3) {
        *len = 2;
        switch (b1) {
            case 0xA1: case 0x81: *stressed=1; return 'a';  /* á Á */
            case 0xA9: case 0x89: *stressed=1; return 'e';  /* é É */
            case 0xAD: case 0x8D: *stressed=1; return 'i';  /* í Í */
            case 0xB3: case 0x93: *stressed=1; return 'o';  /* ó Ó */
            case 0xBA: case 0x9A: *stressed=1; return 'u';  /* ú Ú */
            case 0xBC:            *stressed=0; return 'u';  /* ü   */
            default: *len=1; return 0;
        }
    }

    char c = tolower((char)b0);
    if (c=='a'||c=='e'||c=='i'||c=='o'||c=='u') return c;
    return 0;
}

/* Is the char at position i a "front" vowel (e/i, with or without accent)? */
static int next_is_front_vowel(const unsigned char *s, int i)
{
    if (!s[i]) return 0;
    int st, len;
    char v = decode_vowel(s, i, &st, &len);
    return v=='e' || v=='i';
}

/* ------------------------------------------------------------------ */
/* Stressed-vowel phoneme names                                        */
/* ------------------------------------------------------------------ */
static const char *vowel_ph(char v, int stressed)
{
    switch (v) {
        case 'a': return stressed ? "a1" : "a";
        case 'e': return stressed ? "e1" : "e";
        case 'i': return stressed ? "i1" : "i";
        case 'o': return stressed ? "o1" : "o";
        case 'u': return stressed ? "u1" : "u";
    }
    return "a";
}

/* ------------------------------------------------------------------ */
/* Stress assignment                                                   */
/* Rules: accent mark overrides; else penultimate if word ends        */
/*  vowel/n/s, last syllable otherwise.                               */
/* Returns index (in vowel_positions[]) of stressed vowel, or -1.    */
/* ------------------------------------------------------------------ */

static int count_syllables_and_stress(const unsigned char *s, int len,
                                       int *vpos, int *vcnt, int *has_accent)
{
    int n = 0;
    *has_accent = 0;
    int i = 0;
    while (i < len && n < 32) {
        int st, bl;
        char v = decode_vowel(s, i, &st, &bl);
        if (v) {
            vpos[n++] = i;
            if (st) *has_accent = i;
        }
        i += bl ? bl : 1;
    }
    *vcnt = n;
    return n;
}

/* Which vowel index bears stress? */
static int stressed_vowel_index(const unsigned char *s, int slen,
                                 const int *vpos, int vcnt)
{
    if (vcnt == 0) return -1;
    if (vcnt == 1) return 0;

    /* Check for accent mark */
    for (int i = 0; i < vcnt; i++) {
        int st, bl;
        decode_vowel(s, vpos[i], &st, &bl);
        if (st) return i;
    }

    /* Default stress rules */
    unsigned char last = tolower(s[slen-1]);
    /* last char might be UTF-8; use slen-1 if ASCII */
    if (last == 'a' || last == 'e' || last == 'i' ||
        last == 'o' || last == 'u' || last == 'n' || last == 's') {
        return vcnt >= 2 ? vcnt - 2 : 0;  /* penultimate vowel */
    }
    return vcnt - 1;  /* last vowel */
}

/* ------------------------------------------------------------------ */
/* Main G2P function                                                   */
/* ------------------------------------------------------------------ */

cst_val *es_hts_lts(const cst_lexicon *l, const char *word,
                    const char *pos, const cst_features *feats)
{
    (void)l; (void)pos; (void)feats;

    const unsigned char *s = (const unsigned char *)word;
    int slen = strlen(word);

    /* Collect vowel positions for stress assignment */
    int vpos[32], vcnt = 0, has_accent = 0;
    count_syllables_and_stress(s, slen, vpos, &vcnt, &has_accent);
    int stress_idx = stressed_vowel_index(s, slen, vpos, vcnt);
    int stressed_byte = (stress_idx >= 0 && stress_idx < vcnt)
                        ? vpos[stress_idx] : -1;

    PhBuf pb = {.n = 0};
    int i = 0;
    int word_initial = 1;  /* for rr rule at word start */

    while (i < slen) {
        unsigned char b0 = s[i];
        unsigned char b1 = s[i+1];  /* safe: string is NUL-terminated */

        /* --- Accented / special UTF-8 characters --- */
        if (b0 == 0xC3) {
            int st, bl;
            char v = decode_vowel(s, i, &st, &bl);
            if (v) {
                /* Use stress_idx to determine if THIS vowel position is stressed */
                int this_stressed = (i == stressed_byte);
                pb_push(&pb, vowel_ph(v, this_stressed));
                i += 2;
                word_initial = 0;
                continue;
            }
            /* ñ = 0xC3 0xB1 or Ñ = 0xC3 0x91 */
            if (b1 == 0xB1 || b1 == 0x91) {
                pb_push(&pb, "ny");
                i += 2;
                word_initial = 0;
                continue;
            }
            /* ü = 0xC3 0xBC (already handled above as vowel u) */
            /* unknown 2-byte: skip */
            i += 2;
            continue;
        }

        /* --- ASCII letters --- */
        char c = tolower((char)b0);
        char c2 = tolower((char)b1);

        /* Plain vowels */
        if (c=='a'||c=='e'||c=='i'||c=='o'||c=='u') {
            int this_stressed = (i == stressed_byte);
            pb_push(&pb, vowel_ph(c, this_stressed));
            i++;
            word_initial = 0;
            continue;
        }

        switch (c) {

        case 'b': case 'v':
            pb_push(&pb, "b");
            break;

        case 'c':
            if (c2 == 'h') {
                pb_push(&pb, "ch");
                i++;  /* skip 'h' */
            } else if (next_is_front_vowel(s, i+1)) {
                pb_push(&pb, "th");
            } else {
                pb_push(&pb, "k");
            }
            break;

        case 'd':
            pb_push(&pb, "d");
            break;

        case 'f':
            pb_push(&pb, "f");
            break;

        case 'g':
            if (c2 == 'u') {
                /* gu + front vowel → g (silent u) */
                if (next_is_front_vowel(s, i+2)) {
                    pb_push(&pb, "g");
                    i++;  /* skip u */
                } else {
                    pb_push(&pb, "g");
                }
            } else if (next_is_front_vowel(s, i+1)) {
                pb_push(&pb, "x");
            } else {
                pb_push(&pb, "g");
            }
            break;

        case 'h':
            /* silent in Spanish */
            break;

        case 'j':
            pb_push(&pb, "x");
            break;

        case 'k':
            pb_push(&pb, "k");
            break;

        case 'l':
            if (c2 == 'l') {
                pb_push(&pb, "ll");
                i++;  /* skip second l */
            } else {
                pb_push(&pb, "l");
            }
            break;

        case 'm':
            pb_push(&pb, "m");
            break;

        case 'n':
            pb_push(&pb, "n");
            break;

        case 'p':
            pb_push(&pb, "p");
            break;

        case 'q':
            /* qu → k (skip u) */
            if (c2 == 'u') i++;
            pb_push(&pb, "k");
            break;

        case 'r':
            if (c2 == 'r') {
                pb_push(&pb, "rr");
                i++;  /* skip second r */
            } else if (word_initial) {
                pb_push(&pb, "rr");
            } else {
                /* rr after n, l, s */
                int pi = i - 1;
                char prev = (pi >= 0) ? tolower((char)s[pi]) : 0;
                if (prev == 'n' || prev == 'l' || prev == 's') {
                    pb_push(&pb, "rr");
                } else {
                    pb_push(&pb, "r");
                }
            }
            break;

        case 's':
            pb_push(&pb, "s");
            break;

        case 't':
            pb_push(&pb, "t");
            break;

        case 'w':
            pb_push(&pb, "b");
            break;

        case 'x':
            /* Approximation: x → s (word-initial: "xilófono")
               Between vowels: "taxi" → t a k s i, just use s for simplicity */
            pb_push(&pb, "s");
            break;

        case 'y':
            /* y vowel at end of word or alone → i */
            if (!b1 || !isalpha(b1)) {
                pb_push(&pb, "i");
            } else {
                pb_push(&pb, "ll");
            }
            break;

        case 'z':
            pb_push(&pb, "th");
            break;

        default:
            /* numbers, punctuation, etc. — skip */
            break;
        }

        i++;
        word_initial = 0;
    }

    /* Build cst_val linked list (in reverse, then we build forward) */
    cst_val *phones = NULL;
    for (int j = pb.n - 1; j >= 0; j--)
        phones = cons_val(string_val(pb.p[j]), phones);

    if (!phones)
        phones = cons_val(string_val("pau"), NULL);

    return phones;
}

/* ------------------------------------------------------------------ */
/* Syllable boundary: return TRUE if boundary before phoneme i        */
/* Simple rule: boundary before any phoneme that follows a vowel,     */
/* or that starts a new onset cluster.                                */
/* ------------------------------------------------------------------ */

static int es_is_vowel_ph(const char *ph)
{
    return ph && (ph[0]=='a'||ph[0]=='e'||ph[0]=='i'||ph[0]=='o'||ph[0]=='u');
}

int es_hts_syl_boundary(const cst_item *syl, const cst_val *rest)
{
    (void)syl;
    /* Place boundary if remaining phonemes contain a vowel
       and current syllable already has a vowel */
    if (!rest) return TRUE;

    const char *next_ph = val_string(val_car(rest));

    /* Scan rest for a vowel */
    int rest_has_vowel = 0;
    const cst_val *v = rest;
    while (v) {
        if (es_is_vowel_ph(val_string(val_car(v)))) { rest_has_vowel=1; break; }
        v = val_cdr(v);
    }
    if (!rest_has_vowel) return FALSE;

    /* Check if current syllable already has a vowel */
    const char *cur = ffeature_string(syl, "name");
    if (!es_is_vowel_ph(cur)) return FALSE;

    /* Don't break onset clusters: if next two are consonants, keep together */
    /* Simple: always split before a vowel */
    if (es_is_vowel_ph(next_ph)) return TRUE;

    /* Split after vowel (put single consonant with following vowel) */
    if (val_cdr(rest)) {
        const char *after_next = val_string(val_car(val_cdr(rest)));
        if (es_is_vowel_ph(after_next)) return TRUE;  /* V.CV → split before C */
    }

    return FALSE;
}

/* ------------------------------------------------------------------ */
/* Spanish number expansion                                           */
/* ------------------------------------------------------------------ */

static const char *ones[] = {
    "cero","uno","dos","tres","cuatro","cinco","seis","siete","ocho","nueve",
    "diez","once","doce","trece","catorce","quince",
    "diecis\xc3\xa9is","diecisiete","dieciocho","diecinueve",
    "veinte","veintiuno","veintid\xc3\xb3s","veintitr\xc3\xa9s","veinticuatro",
    "veinticinco","veintis\xc3\xa9is","veintisiete","veintiocho","veintinueve"
};
static const char *tens[] = {
    "","","veinte","treinta","cuarenta","cincuenta","sesenta","setenta","ochenta","noventa"
};
static const char *hundreds[] = {
    "","cien","doscientos","trescientos","cuatrocientos","quinientos",
    "seiscientos","setecientos","ochocientos","novecientos"
};

/* Appends words for n (0..999) to the cst_val list *head (prepend-style).
   Returns updated head. Caller reverses at the end. */
static cst_val *append_num(cst_val *head, int n)
{
    if (n == 0) return cons_val(string_val("cero"), head);

    if (n >= 100) {
        int h = n / 100;
        int rest = n % 100;
        if (n == 100) {
            head = cons_val(string_val("cien"), head);
        } else {
            head = cons_val(string_val(hundreds[h]), head);
            if (rest) head = append_num(head, rest);
        }
        return head;
    }

    if (n < 30) {
        head = cons_val(string_val(ones[n]), head);
        return head;
    }

    int t = n / 10, u = n % 10;
    head = cons_val(string_val(tens[t]), head);
    if (u) {
        head = cons_val(string_val("y"), head);
        head = cons_val(string_val(ones[u]), head);
    }
    return head;
}

static cst_val *es_expand_number(int n)
{
    cst_val *rev = NULL;

    if (n == 0) return cons_val(string_val("cero"), NULL);

    if (n >= 1000) {
        int miles = n / 1000;
        int rest  = n % 1000;
        if (miles == 1) {
            rev = cons_val(string_val("mil"), rev);
        } else {
            rev = append_num(rev, miles);
            rev = cons_val(string_val("mil"), rev);
        }
        if (rest) rev = append_num(rev, rest);
    } else {
        rev = append_num(rev, n);
    }

    /* reverse the prepended list */
    cst_val *fwd = NULL;
    while (rev) {
        fwd = cons_val(val_car(rev), fwd);
        cst_val *tmp = (cst_val *)val_cdr(rev);
        cst_free(rev);
        rev = tmp;
    }
    return fwd;
}

static int is_all_digits(const char *s)
{
    if (!s || !*s) return 0;
    for (; *s; s++) if (!isdigit((unsigned char)*s)) return 0;
    return 1;
}

/* tokentowords override: expand numbers, pass rest as-is */
cst_val *es_hts_tokentowords(cst_item *token)
{
    const char *name = item_name(token);
    if (!name) return cons_val(string_val(""), NULL);

    if (is_all_digits(name)) {
        int n = atoi(name);
        if (n >= 0 && n < 100000)
            return es_expand_number(n);
    }

    return cons_val(string_val(name), NULL);
}

/* ------------------------------------------------------------------ */
/* Lexicon init                                                        */
/* ------------------------------------------------------------------ */

static cst_lexicon es_hts_lex_storage;

cst_lexicon *es_hts_lex_init(void)
{
    if (es_hts_lex_storage.lts_function)
        return &es_hts_lex_storage;

    cst_lexicon *l = &es_hts_lex_storage;
    l->name         = "es_hts_lex";
    l->lts_function = es_hts_lts;
    l->syl_boundary = es_hts_syl_boundary;
    l->postlex      = NULL;
    return l;
}
