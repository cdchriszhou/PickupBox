cmake_minimum_required(VERSION 3.21)
project(FH_KAOK LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Multimedia Network)

qt_add_executable(FH_KAOK
    src/main.cpp
    src/MainWindow.h
    src/MainWindow.cpp
    src/AudioEngine.h
    src/AudioEngine.cpp
    src/CassetteDeckWidget.h
    src/CassetteDeckWidget.cpp
    src/PaintKit.h
    src/PaintKit.cpp
    src/UiTheme.h
    src/UiTheme.cpp
    src/RadioBrowser.h
    src/RadioBrowser.cpp
    resources/fh_kaok.qrc
)

target_link_libraries(FH_KAOK PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Multimedia
    Qt6::Network
)

if(WIN32)
    set_target_properties(FH_KAOK PROPERTIES WIN32_EXECUTABLE TRUE)
    # Embed multi-size ICO so Explorer desktop / taskbar shortcuts look correct
    set(FH_KAOK_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/fh-kaok.ico")
    string(REPLACE "\\" "/" FH_KAOK_ICON "${FH_KAOK_ICON}")
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/resources/fh_kaok.rc.in
        ${CMAKE_CURRENT_BINARY_DIR}/fh_kaok.rc
        @ONLY
    )
    target_sources(FH_KAOK PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/fh_kaok.rc)
endif()
