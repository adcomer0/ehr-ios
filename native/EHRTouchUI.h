#ifndef EHR_TOUCH_UI_H
#define EHR_TOUCH_UI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// These are our presentation values, never copied IL2CPP value layouts.
typedef struct {
  float r, g, b, a;
} EHRTouchColor;
typedef struct {
  float x, y, width, height;
} EHRTouchRect;
typedef struct {
  EHRTouchColor text, fill, edge;
  float radius;
} EHRTouchState;
typedef struct {
  EHRTouchState normal, hover, active;
  float font_size;
  int32_t font_style, alignment, word_wrap, rich_text;
  EHRTouchColor tint;
} EHRTouchStyle;
typedef struct {
  uint64_t key;
  uint32_t kind, flags;
  EHRTouchRect rect;
  float value, minimum, maximum;
  EHRTouchStyle style;
} EHRTouchItem;
typedef struct {
  uint32_t version, size, should_draw, reserved;
  float pixels_per_point_x, pixels_per_point_y, width, height;
  float safe_left, safe_top, safe_right, safe_bottom;
} EHRTouchFrame;
enum { EHR_TOUCH_BOX = 1, EHR_TOUCH_LABEL = 2, EHR_TOUCH_BUTTON = 3, EHR_TOUCH_SLIDER = 4 };
// Main-thread only. UTF-8 and structs are copied during each call. No callback
// retains managed memory. A queued press is consumed only by the same currently
// emitted key+label; End removes missing widgets and their pending inputs.
typedef struct {
  uint32_t version, size;
  int32_t (*is_main_thread)(void);
  int32_t (*begin)(float width, float height, EHRTouchFrame *frame);
  int32_t (*end)(int32_t commit);
  int32_t (*item)(const EHRTouchItem *, const uint8_t *, size_t, float *, int32_t *);
  int32_t (*begin_scroll)(uint64_t, const EHRTouchRect *, const EHRTouchRect *, float, float, float,
                          float, float *, float *);
  int32_t (*end_scroll)(void);
  int32_t (*move_window)(EHRTouchRect *, float title_height);
  int32_t (*hide)(void);
} EHRTouchUIV1;
const EHRTouchUIV1 *EHRTouchUIGetV1(void);
// Original UIKit views only, programmatic events, no game commands or input.
int32_t EHRTouchUISelfTest(int32_t *proof, size_t count);
int32_t ehr_touch_ui_bind_v1(const EHRTouchUIV1 *, size_t);
int32_t ehr_touch_ui_managed_contract_test(int32_t *, size_t);
#ifdef __cplusplus
}
static_assert(sizeof(EHRTouchColor) == 16, "color");
static_assert(sizeof(EHRTouchRect) == 16, "rect");
static_assert(sizeof(EHRTouchState) == 52, "state");
static_assert(sizeof(EHRTouchStyle) == 192, "style");
static_assert(sizeof(EHRTouchItem) == 240, "item");
static_assert(sizeof(EHRTouchFrame) == 48, "frame");
static_assert(sizeof(EHRTouchUIV1) == 72, "table");
#endif
#endif
