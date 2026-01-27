// waylandconnect-adapter/contents/code/main.js

function movePointer(dx, dy) {
    let currentPos = workspace.cursorPos;
    workspace.cursorPos = {
        x: currentPos.x + dx,
        y: currentPos.y + dy
    };
}

// We expose this via a shortcut or a global function that KWin's DBus interface can trigger
globalThis.waylandConnectMove = movePointer;

console.log("WaylandConnect: Adapter active. Integration ready.");
