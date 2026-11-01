# Supported stock map tokens

`MAP_ROTATION` accepts a space-separated list of the **85 exact stock mission tokens** exposed by both `mission.lvl` and `DSManager.exe` in the original Battlefront II v1.1 dedicated-server payload.

- Era: `c` = Clone Wars; `g` = Galactic Civil War.
- Modes: `con` = Conquest; `ctf` = two-flag CTF; `1flag` = one-flag CTF; `hunt` = Hunt; `eli` = Hero Assault; `ass` = Space Assault.
- Unknown combinations and tokens with unsafe characters fail startup. At least one supported token is required.
- These are stock combinations only. Custom maps require matching operator-supplied server and client assets and are not covered by this candidate.

## Ground maps

- **Coruscant:** `cor1c_con cor1c_ctf cor1g_con cor1g_ctf`
- **Dagobah:** `dag1c_con dag1c_ctf dag1g_con dag1g_ctf`
- **Death Star:** `dea1c_1flag dea1c_con dea1g_1flag dea1g_con`
- **Endor:** `end1g_1flag end1g_con end1g_hunt`
- **Felucia:** `fel1c_1flag fel1c_con fel1g_1flag fel1g_con`
- **Geonosis:** `geo1c_con geo1c_ctf geo1c_hunt`
- **Hoth:** `hot1g_1flag hot1g_con hot1g_hunt`
- **Kamino:** `kam1c_1flag kam1c_con kam1g_1flag kam1g_con`
- **Kashyyyk:** `kas2c_con kas2c_ctf kas2c_hunt kas2g_con kas2g_ctf`
- **Mustafar:** `mus1c_con mus1c_ctf mus1g_con mus1g_ctf`
- **Mygeeto:** `myg1c_con myg1c_ctf myg1g_con myg1g_ctf`
- **Naboo:** `nab2c_con nab2c_ctf nab2c_hunt nab2g_con nab2g_ctf`
- **Polis Massa:** `pol1c_con pol1c_ctf pol1g_con pol1g_ctf`
- **Tantive IV:** `tan1c_1flag tan1c_con tan1g_1flag tan1g_con`
- **Tatooine — Mos Eisley:** `tat2c_con tat2c_ctf tat2g_con tat2g_ctf tat2g_eli tat2g_hunt`
- **Tatooine — Jabba's Palace:** `tat3c_1flag tat3c_con tat3g_1flag tat3g_con`
- **Utapau:** `uta1c_1flag uta1c_con uta1g_1flag uta1g_con`
- **Yavin 4 — Temple:** `yav1c_1flag yav1c_con yav1g_1flag yav1g_con`

## Space maps

- **Space Yavin:** `spa1g_1flag spa1g_ass`
- **Space Kashyyyk:** `spa3c_1flag spa3c_ass`
- **Space Mygeeto:** `spa6c_1flag spa6c_ass`
- **Space Felucia:** `spa7c_1flag spa7c_ass`
- **Space Hoth:** `spa8g_1flag spa8g_ass`
- **Space Tatooine:** `spa9g_1flag spa9g_ass`
