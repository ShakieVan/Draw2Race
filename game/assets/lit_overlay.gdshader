shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
// Zusatzlicht (Laternen/Flutlicht) als material_overlay, einseitig. Inhalt und Erklärung: lit_overlay.gdshaderinc.
#include "res://assets/lit_overlay.gdshaderinc"
