shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Zusatzlicht wie lit_overlay.gdshader, aber beidseitig (offene Bänder, Looping): Rückseiten werden mit umgedrehter Normale beleuchtet.
#define TWO_SIDED
#include "res://assets/lit_overlay.gdshaderinc"
