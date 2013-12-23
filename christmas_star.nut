// Strip of 16 WS2801 RGB LED drivers
server.log("ledstrip starting");

local r=0, g=0, b=0;

function timer()
{
    imp.wakeup(0.01, timer);

    r = (r+3) % 51000;
    g = (g+11) % 51000;
    b = (b+7) % 51000;

    local r3 = r/100;
    local g3 = g/100;
    local b3 = b/100;

    local r2 = (r3 > 255) ? 510-r3 : r3;
    local g2 = (g3 > 255) ? 510-g3 : g3;
    local b2 = (b3 > 255) ? 510-b3 : b3;

    local out = blob(48);
    // for (local i=0; i<16; ++i) {
    for (local i=0; i<10; ++i) {
        out.writen(r2, 'b');
        out.writen(g2, 'b');
        out.writen(b2, 'b');
    }

    hardware.spi257.write(out);
    // WS2801 datasheet says idle for 500us to latch
    imp.sleep(0.001);
}

hardware.spi257.configure(SIMPLEX_TX, 15000); // Datasheet says max 25MHz
hardware.pin5.configure(DIGITAL_OUT);
hardware.pin5.write(0);
imp.sleep(0.01);
hardware.pin5.write(1);
hardware.configure(SPI_257);
timer();
server.log("ledstrip started");
