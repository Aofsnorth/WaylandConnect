import QtQuick 2.0
import org.kde.kwin 3.0

Item {
    id: root
    
    // Listen to generic DBus signals is hard in KWin QML, 
    // but we can expose a method and have Rust call it,
    // or use a helper that KWin provides.
    
    // For PoC, the most reliable way on Wayland is for Rust to call:
    // org.kde.KWin /Scripting org.kde.kwin.Scripting.runScript
    
    function moveCursor(dx, dy) {
        var currentPos = workspace.cursorPos;
        workspace.cursorPos = {
            x: currentPos.x + dx,
            y: currentPos.y + dy
        };
    }

    Component.onCompleted: {
        console.log("WaylandConnect: QML Adapter Loaded");
    }
}
