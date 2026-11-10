APP_NAME    := PickupBox
# Override when build/ is root-owned after a bad PKG relocate:
#   make APP_BUNDLE=dist/work/PickupBox.app OBJ_DIR=dist/work/obj
APP_BUNDLE  ?= build/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RES_DIR     := $(CONTENTS)/Resources
OBJ_DIR     ?= build/obj

CXX         := clang++
OBJCXXFLAGS := -fobjc-arc -std=c++17 -ObjC++ -Wall -Wextra \
               -Wno-unused-parameter -O2 \
               -ISources -ISources/Views -ISources/Helpers
OBJCXXFLAGS := $(OBJCXXFLAGS) -ISources/Audio
LDFLAGS     := -framework Cocoa -framework AppKit -framework Foundation -framework QuartzCore \
               -framework AVFoundation -framework MediaToolbox -framework Accelerate -framework CoreMedia \
               -framework UniformTypeIdentifiers

SRCS := \
	Sources/main.mm \
	Sources/AppDelegate.mm \
	Sources/Audio/AudioEngine.mm \
	Sources/Audio/LyricsService.mm \
	Sources/Audio/RadioCatalog.mm \
	Sources/Audio/RadioBrowserService.mm \
	Sources/Helpers/DrawingHelpers.mm \
	Sources/Helpers/BrandProfile.mm \
	Sources/Helpers/MenuLocalization.mm \
	Sources/Views/KnobView.mm \
	Sources/Views/FaderView.mm \
	Sources/Views/SpectrumView.mm \
	Sources/Views/SpeakerView.mm \
	Sources/Views/WorldTunerView.mm \
	Sources/Views/CassetteView.mm \
	Sources/Views/MediaPanelView.mm \
	Sources/Views/ToggleButtonView.mm \
	Sources/Views/MetalKeyView.mm \
	Sources/Views/MainConsoleView.mm

OBJS := $(patsubst Sources/%.mm,$(OBJ_DIR)/%.o,$(SRCS))

.PHONY: all clean run open dist installer

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(MACOS_DIR)/$(APP_NAME) Resources/Info.plist
	@mkdir -p $(RES_DIR)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(RES_DIR)/; fi
	@if [ -f Resources/AppIcon.png ]; then cp Resources/AppIcon.png $(RES_DIR)/; fi
	@if [ -d Resources/Brands ]; then mkdir -p $(RES_DIR)/Brands && cp -R Resources/Brands/. $(RES_DIR)/Brands/; fi
	@if [ -f Resources/demo_tone.wav ]; then cp Resources/demo_tone.wav $(RES_DIR)/; fi
	@find $(APP_BUNDLE) -name '._*' -delete 2>/dev/null || true
	@touch $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

$(MACOS_DIR)/$(APP_NAME): $(OBJS)
	@mkdir -p $(MACOS_DIR)
	$(CXX) $(OBJS) -o $@ $(LDFLAGS)

$(OBJ_DIR)/%.o: Sources/%.mm
	@mkdir -p $(dir $@)
	$(CXX) $(OBJCXXFLAGS) -c $< -o $@

run: all
	open "$(APP_BUNDLE)"

open: run

clean:
	rm -rf build dist

# Standard installer: PKG (向导) + DMG (拖拽 / 双击安装)
dist installer:
	@chmod +x Packaging/build_installer.sh Packaging/scripts/postinstall
	./Packaging/build_installer.sh
