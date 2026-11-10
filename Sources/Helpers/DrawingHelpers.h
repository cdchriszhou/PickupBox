#pragma once

#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif

NSColor *SKAmberColor(void);
NSColor *SKAmberDimColor(void);
NSColor *SKPanelColor(void);
NSColor *SKMetalDarkColor(void);
NSColor *SKMetalMidColor(void);
NSColor *SKMetalLightColor(void);
NSColor *SKRedLEDColor(void);

void SKFillBrushedMetal(NSRect rect, CGFloat darkness);
void SKDrawInsetBevel(NSRect rect, CGFloat radius);
void SKDrawRaisedBevel(NSRect rect, CGFloat radius);
void SKDrawLEDBar(NSRect rect, CGFloat level, BOOL vertical);
/// Segmented VU / signal meter with glass well (vertical = bottom→top)
void SKDrawSegmentMeter(NSRect rect, CGFloat level, NSInteger segments, BOOL vertical);
/// Jewel-style status LED
void SKDrawJewelLED(NSRect rect, NSColor *color, BOOL on);
void SKDrawGlowText(NSString *text, NSRect rect, NSFont *font, NSColor *color, NSTextAlignment align);
void SKDrawScrew(NSPoint center, CGFloat radius);
/// Vertical/horizontal punched vent grille (hi-fi side cheek)
void SKDrawVentGrille(NSRect rect, BOOL vertical);
/// Draw a rack-mount module face with title strip and corner screws
void SKDrawRackModule(NSRect rect, NSString *title, CGFloat darkness);
void SKDrawVFDScreen(NSRect rect);
/// 7-segment style VFD digit (0–9). Digits outside 0–9 draw blank skeleton only.
void SKDrawVFDDigit(NSRect rect, NSInteger digit, NSColor *color);
/// Draw pattern using chars 0–9, ':', '-', '.'; `align` Left/Center/Right.
void SKDrawVFDPattern(NSRect rect, NSString *pattern, NSColor *color, NSTextAlignment align);
/// Draw MM:SS sleep / timer readout in 7-segment style.
void SKDrawVFDTime(NSRect rect, NSInteger totalSeconds, NSColor *color, NSTextAlignment align);

#ifdef __cplusplus
}
#endif
