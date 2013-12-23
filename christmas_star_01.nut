

//****************************************************************************
//
function Color(out, r, g, b) {
    out.writen(r, 'b');
    out.writen(g, 'b');
    out.writen(b, 'b');
    return out;
}

//****************************************************************************
//
function Wheel(out, WheelPos) {
    if (WheelPos < 85) {
        return Color(out, WheelPos * 3, 255 - WheelPos * 3, 0);
    }
    else if (WheelPos < 170)   {
        WheelPos -= 85;
        return Color(out, 255 - WheelPos * 3, 0, WheelPos * 3);
    } else {
        WheelPos -= 170;
        return Color(out, 0, WheelPos * 3, 255 - WheelPos * 3);
    }
}

//****************************************************************************
//
function hexToInteger(hex) {
    local result = 0;
    local shift = hex.len() * 4;

    // For each digit..
    for(local d=0; d<hex.len(); d++) {
        local digit;

        // Convert from ASCII Hex to integer
        if(hex[d] >= 0x61) {
            digit = hex[d] - 0x57;
        } else if(hex[d] >= 0x41) {
            digit = hex[d] - 0x37;
        } else {
            digit = hex[d] - 0x30;
        }

        // Accumulate digit
        shift -= 4;
        result += digit << shift;
    }

    return result;
}

local cache = null;
local frames_count = 0;
local count = 0;
local numPixels = 12;
local writeWait = 0.1;

local rainbow_count = 0;

//****************************************************************************
//
function run_cache() {

    if(cache != null) {
        imp.wakeup((frames_count * writeWait)+1, run_cache);
        //server.log("wake up : run_cache");
        foreach(frame,out in cache) {
            //server.log(typeof out);
            hardware.spi257.write(out);
            //server.log(format("cache frame %i, %i", frame, count));
            count++;
            imp.sleep(writeWait);
        }
    } else {
        imp.wakeup((256*0.0020), run_cache);
        server.log("nothing, doing a rainbow");
        server.log(rainbow_count);
        if(rainbow_count < 10) {
            for(local j=0; j < 256; j++) {
                local out = blob(3*numPixels);
                for (local i=0; i<numPixels; ++i) {
                    out = Wheel( out, ((i * 256 / numPixels) + j) % 256);
                }
                hardware.spi257.write(out);
                // WS2801 datasheet says idle for 500us to latch
                imp.sleep(0.005);
            }
        } else if(rainbow_count < 20) {

            //rainbow
            for(local j=0; j < 256; j++) {
                local out = blob(3*numPixels);
                for (local i=0; i<numPixels; ++i) {
                    out = Wheel( out, (i + j) % 255);

                }
                hardware.spi257.write(out);
                imp.sleep(writeWait);
            }
        } else {
            rainbow_count = 0;
            imp.sleep(writeWait*10);
        }
        rainbow_count++;
    }
}

server.log("spi config start");
hardware.spi257.configure(SIMPLEX_TX, 15000); // Datasheet says max 25MHz
hardware.pin5.configure(DIGITAL_OUT);
hardware.pin5.write(0);
imp.sleep(0.01);
hardware.pin5.write(1);
hardware.configure(SPI_257);
server.log("spi config end");

run_cache();
// End of code.
