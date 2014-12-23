//
// Electric Imp Christmas Tree Star
//
// Ws2801 driving code derived from:
// https://github.com/jamesjnadeau/ws2801_electircimp
//
// SX1509 IO Expander derived from:
// https://github.com/electricimp/examples/blob/master/hannah/hannah_complete.nut
//
// For IO Expander:
//
//     Copyright (C) 2013 electric imp, inc.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

//##########################################################################
//
//
class Bullwinkle
{
    _handlers = null;
    _sessions = null;
    _partner  = null;
    _history  = null;
    _timeout  = 10;
    _retries  = 1;


    // .........................................................................
    constructor() {
        const BULLWINKLE = "bullwinkle";

        _handlers = { timeout = null, receive = null };
        _partner  = is_agent() ? device : agent;
        _sessions = { };
        _history  = { };

        // Incoming message handler
        _partner.on(BULLWINKLE, _receive.bindenv(this));
    }


    // .........................................................................
    function send(command, params = null) {

        // Generate an unique id
        local id = _generate_id();

        // Create and store the session
        _sessions[id] <- Bullwinkle_Session(this, id, _timeout, _retries);

        return _sessions[id].send("send", command, params);
    }


    // .........................................................................
    function ping() {

        // Generate an unique id
        local id = _generate_id();

        // Create and store the session
        _sessions[id] <- Bullwinkle_Session(this, id, _timeout, _retries);

        // Send it
        return _sessions[id].send("ping");
    }


    // .........................................................................
    function is_agent() {
        return (imp.environment() == ENVIRONMENT_AGENT);
    }

    // .........................................................................
    static function _getCmdKey(cmd) {
        return BULLWINKLE + "_" + cmd;
    }

    // .........................................................................
    function on(command, callback) {
        local cmdKey = Bullwinkle._getCmdKey(command);

        if (cmdKey in _handlers) {
            _handlers[cmdKey] = callback;
        } else {
            _handlers[cmdKey] <- callback
        }
    }
    // .........................................................................
    function onreceive(callback) {
        _handlers.receive <- callback;
    }


    // .........................................................................
    function ontimeout(callback, timeout = null) {
        _handlers.timeout <- callback;
        if (timeout != null) _timeout = timeout;
    }


    // .........................................................................
    function set_timeout(timeout) {
        _timeout = timeout;
    }


    // .........................................................................
    function set_retries(retries) {
        _retries = retries;
    }


    // .........................................................................
    function _generate_id() {
        // Generate an unique id
        local id = null;
        do {
            id = math.rand();
        } while (id in _sessions);
        return id;
    }

    // .........................................................................
    function _is_unique(context) {

        // Clean out old id's from the history
        local now = time();
        foreach (id,t in _history) {
            if (now - t > 100) {
                delete _history[id];
            }
        }

        // Check the current context for uniqueness
        local id = context.id;
        if (id in _history) {
            return false;
        } else {
            _history[id] <- time();
            return true;
        }
    }

    // .........................................................................
    function _clone_context(ocontext) {
        local context = {};
        foreach (k,v in ocontext) {
            switch (k) {
                case "type":
                case "id":
                case "time":
                case "command":
                case "params":
                    context[k] <- v;
            }
        }
        return context;
    }


    // .........................................................................
    function _end_session(id) {
        if (id in _sessions) {
            delete _sessions[id];
        }
    }


    // .........................................................................
    function _receive(context) {
        local id = context.id;
        switch (context.type) {
            case "send":
            case "ping":
                // build the command string
                local cmdKey = Bullwinkle._getCmdKey(context.command);

                // Immediately ack the message
                local response = { type = "ack", id = id, time = Bullwinkle_Session._timestamp() };
                if (!_handlers.receive && !_handlers[cmdKey]) {
                    response.type = "nack";
                }
                _partner.send(BULLWINKLE, response);

                // Then handed on to the callback
                if (context.type == "send" && (_handlers.receive || _handlers[cmdKey]) && _is_unique(context)) {
                    try {
                        // Prepare a reply function for shipping a reply back to the sender
                        context.reply <- function (reply) {
                            local response = { type = "reply", id = id, time = Bullwinkle_Session._timestamp() };
                            response.reply <- reply;
                            _partner.send(BULLWINKLE, response);
                        }.bindenv(this);

                        // Fire the callback
                        if (_handlers[cmdKey]) {
                            _handlers[cmdKey](context);
                        } else {
                            _handlers.receive(context);
                        }
                    } catch (e) {
                        // An unhandled exception should be sent back to the sender
                        local response = { type = "exception", id = id, time = Bullwinkle_Session._timestamp() };
                        response.exception <- e;
                        _partner.send(BULLWINKLE, response);
                    }
                }
                break;

            case "nack":
            case "ack":
                // Pass this packet to the session handler
                if (id in _sessions) {
                    _sessions[id]._ack(context);
                }
                break;

            case "reply":
                // This is a reply for an sent message
                if (id in _sessions) {
                    _sessions[id]._reply(context);
                }
                break;

            case "exception":
                // Pass this packet to the session handler
                if (id in _sessions) {
                    _sessions[id]._exception(context);
                }
                break;

            default:
                throw "Unknown context type: " + context.type;

        }
    }

}

// -----------------------------------------------------------------------------
class Bullwinkle_Session
{
    _handlers = null;
    _parent = null;
    _context = null;
    _timer = null;
    _timeout = null;
    _acked = false;
    _retries = null;

    // .........................................................................
    constructor(parent, id, timeout = 0, retries = 1) {
        _handlers = { ack = null, reply = null, timeout = null, exception = null };
        _parent = parent;
        _timeout = timeout;
        _retries = retries;
        _context = { time = _timestamp(), id = id };
    }

    // .........................................................................
    function onack(callback) {
        _handlers.ack = callback;
        return this;
    }

    // .........................................................................
    function onreply(callback) {
        _handlers.reply = callback;
        return this;
    }

    // .........................................................................
    function ontimeout(callback) {
        _handlers.timeout = callback;
        return this;
    }

    // .........................................................................
    function onexception(callback) {
        _handlers.exception = callback;
        return this;
    }

    // .........................................................................
    function send(type = "resend", command = null, params = null) {

        _retries--;

        if (type != "resend") {
            _context.type <- type;
            _context.command <- command;
            _context.params <- params;
        }

        if (_timeout > 0) _set_timer(_timeout);
        _parent._partner.send(BULLWINKLE, _context);

        return this;
    }

    // .........................................................................
    function _set_timer(timeout) {

        // Stop any current timers
        _stop_timer();

        // Start a fresh timer
        _timer = imp.wakeup(_timeout, _ontimeout.bindenv(this));
    }

    // .........................................................................
    function _ontimeout() {

        // Close down the timer and session
        _timer = null;

        if (!_acked && _retries > 0) {
            // Retry is required
            send();
        } else {
            // Close off this dead session
            _parent._end_session(_context.id)

            // If we are still waiting for an ack, throw a callback
            if (!_acked) {
                _context.latency <- _timestamp_diff(_context.time, _timestamp());
                if (_handlers.timeout) {
                    // Send the context to the session timeout handler
                    _handlers.timeout(_context);
                } else if (_parent._handlers.timeout) {
                    // Send the context to the global timeout handler
                    _parent._handlers.timeout(_context);
                }
            }
        }
    }

    // .........................................................................
    function _stop_timer() {
        if (_timer) imp.cancelwakeup(_timer);
        _timer = null;
    }

    // .........................................................................
    function _timestamp() {
        if (Bullwinkle.is_agent()) {
            local d = date();
            return format("%d.%06d", d.time, d.usec);
        } else {
            local d = math.abs(hardware.micros());
            return format("%d.%06d", d/1000000, d%1000000);
        }
    }


    // .........................................................................
    function _timestamp_diff(ts0, ts1) {
        // server.log(ts0 + " > " + ts1)
        local t0 = split(ts0, ".");
        local t1 = split(ts1, ".");
        local diff = (t1[0].tointeger() - t0[0].tointeger()) + (t1[1].tointeger() - t0[1].tointeger()) / 1000000.0;
        return math.fabs(diff);
    }


    // .........................................................................
    function _ack(context) {
        // Restart the timeout timer
        _set_timer(_timeout);

        // Calculate the round trip latency and mark the session as acked
        _context.latency <- _timestamp_diff(_context.time, _timestamp());
        _acked = true;

        // Fire a callback
        if (_handlers.ack) {
            _handlers.ack(_context);
        }

    }


    // .........................................................................
    function _reply(context) {
        // We can stop the timeout timer now
        _stop_timer();

        // Fire a callback
        if (_handlers.reply) {
            _context.reply <- context.reply;
            _handlers.reply(_context);
        }

        // Remove the history of this message
        _parent._end_session(_context.id)
    }


    // .........................................................................
    function _exception(context) {
        // We can stop the timeout timer now
        _stop_timer();

        // Fire a callback
        if (_handlers.exception) {
            _context.exception <- context.exception;
            _handlers.exception(_context);
        }

        // Remove the history of this message
        _parent._end_session(_context.id)
    }

}

//
// ------ [ Imp pins ] ------
// Pin 1    Digital input      Interrupt from GPIO expander
// Pin 2    SPI                Unused (can we re-use this?)
// Pin 5    SPI                WS2801 string of lights (yellow/white)
// Pin 7    SPI                WS2801 string of lights (green)
// Pin 8    I2C SCL
// Pin 9    I2C SDA


// ------ [ I2C Addresses ] ------
// 0x7C/0x3E   SX1509BULTRT        IO Expander

const ERR_NO_DEVICE = "The device at I2C address 0x%02x is disabled.";
const ERR_I2C_READ = "I2C Read Failure. Device: 0x%02x Register: 0x%02x";
const ERR_BAD_TIMER = "You have to start %s with an interval and callback";
const ERR_WRONG_DEVICE = "The device at I2C address 0x%02x is not a %s.";

//------------------------------------------------------------------------------
// This class interfaces with the SX1509 IO expander. It sits on the
// I2C bus and data can be directed to the connected devices via its
// I2C address. Interrupts from the devices can be fed back to the imp
// via the configured imp hardware pin.
//
class SX1509 {
  // Private variables
  //
  _i2c       = null;
  _addr      = null;
  _callbacks = null;
  _int_pin   = null;

  // I/O Expander internal registers
  //
  static BANK_A = {
    REGDATA    = 0x11,
    REGDIR     = 0x0F,
    REGPULLUP  = 0x07,
    REGPULLDN  = 0x09,
    REGINTMASK = 0x13,
    REGSNSHI   = 0x16,
    REGSNSLO   = 0x17,
    REGINTSRC  = 0x19,
    REGINPDIS  = 0x01,
    REGOPENDRN = 0x0B,
    REGLEDDRV  = 0x21,
    REGCLOCK   = 0x1E,
    REGMISC    = 0x1F,
    REGRESET   = 0x7D
  };

  static BANK_B = {
    REGDATA    = 0x10,
    REGDIR     = 0x0E,
    REGPULLUP  = 0x06,
    REGPULLDN  = 0x08,
    REGINTMASK = 0x12,
    REGSNSHI   = 0x14,
    REGSNSLO   = 0x15,
    REGINTSRC  = 0x18,
    REGINPDIS  = 0x00,
    REGOPENDRN = 0x0A,
    REGLEDDRV  = 0x20,
    REGCLOCK   = 0x1E,
    REGMISC    = 0x1F,
    REGRESET   = 0x7D
  };

  //***********************************************************************
  //
  // Constructor requires the i2c bus, the address on that bus and
  // the hardware pin to use for interrupts These should all be
  // configured before use here.
  //
  constructor(i2c, address, int_pin) {
    _i2c  = i2c;
    _addr = address;
    _callbacks = [];
    _callbacks.resize(16, null);
    _int_pin = int_pin;

    reset();
    clearAllIrqs();
  }

  //***********************************************************************
  //                    ---- Low level functions ----
  //***********************************************************************

  //***********************************************************************
  //
  // Reads a single byte from a registry
  //
  function readReg(register) {
    local data = _i2c.read(_addr, format("%c", register), 1);
    if (data == null) {
      server.error(format(ERR_I2C_READ, _addr, register));
      return -1;
    }
    return data[0];
  }

  //***********************************************************************
  //
  // Writes a single byte to a registry
  //
  function writeReg(register, data) {
    _i2c.write(_addr, format("%c%c", register, data));
    // server.log(format("Setting device 0x%02X register 0x%02X to 0x%02X",
    //         _addr, register, data));
  }

  //***********************************************************************
  //
  // Changes one bit out of the selected register (byte)
  //
  function writeBit(register, bitn, level) {
    local value = readReg(register);
    value = (level == 0)?(value & ~(1<<bitn)):(value | (1<<bitn));
    writeReg(register, value);
  }

  //***********************************************************************
  //
  // Writes a registry but masks specific bits. Similar to writeBit
  // but for multiple bits.
  //
  function writeMasked(register, data, mask) {
    local value = readReg(register);
    value = (value & ~mask) | (data & mask);
    writeReg(register, value);
  }

  //***********************************************************************
  //
  // set or clear a selected GPIO pin, 0-16
  function setPin(gpio, level) {
    writeBit(bank(gpio).REGDATA, gpio % 8, level ? 1 : 0);
  }

  //***********************************************************************
  //
  // configure specified GPIO pin as input(0) or output(1)
  function setDir(gpio, output) {
    writeBit(bank(gpio).REGDIR, gpio % 8, output ? 0 : 1);
  }

  //***********************************************************************
  //
  // enable or disable input buffers
  function setInputBuffer(gpio, enable) {
    writeBit(bank(gpio).REGINPDIS, gpio % 8, enable ? 0 : 1);
  }

  //***********************************************************************
  //
  // enable or disable open drain
  function setOpenDrain(gpio, enable) {
    writeBit(bank(gpio).REGOPENDRN, gpio % 8, enable ? 1 : 0);
  }

  //***********************************************************************
  //
  // enable or disable internal pull up resistor for specified GPIO
  function setPullUp(gpio, enable) {
    writeBit(bank(gpio).REGPULLUP, gpio % 8, enable ? 1 : 0);
  }

  //***********************************************************************
  //
  // enable or disable internal pull down resistor for specified GPIO
  function setPullDn(gpio, enable) {
    writeBit(bank(gpio).REGPULLDN, gpio % 8, enable ? 1 : 0);
  }

  //***********************************************************************
  //
  // configure whether specified GPIO will trigger an interrupt
  function setIrqMask(gpio, enable) {
    writeBit(bank(gpio).REGINTMASK, gpio % 8, enable ? 0 : 1);
  }

  //***********************************************************************
  //
  // clear interrupt on specified GPIO
  function clearIrq(gpio) {
    writeBit(bank(gpio).REGINTMASK, gpio % 8, 1);
  }

  //***********************************************************************
  //
  // get state of specified GPIO
  function getPin(gpio) {
    return ((readReg(bank(gpio).REGDATA) & (1<<(gpio%8))) ? 1 : 0);
  }

  //***********************************************************************
  //
  // resets the device with a software reset
  function reboot() {
    writeReg(bank(0).REGRESET, 0x12);
    writeReg(bank(0).REGRESET, 0x34);
  }

  //***********************************************************************
  //
  // configure which callback should be called for each pin transition
  function setCallback(gpio, _callback) {
    _callbacks[gpio] = _callback;

    // Initialize the interrupt Pin
    hardware.pin1.configure(DIGITAL_IN_PULLUP, fire_callback.bindenv(this));
  }

  //***********************************************************************
  //
  // finds and executes the callback after the irq pin (pin 1) fires
  function fire_callback() {
    local irq = getIrq();
    clearAllIrqs();
    for (local i = 0; i < 16; i++){
      if ( (irq & (1 << i)) && (typeof _callbacks[i] == "function")){
        _callbacks[i](getPin(i));
      }
    }
  }


  //***********************************************************************
  //                  ---- High level functions ----
  //***********************************************************************


  //***********************************************************************
  //
  // Write registers to default values
  function reset(){
    writeReg(BANK_A.REGDIR, 0xFF);
    writeReg(BANK_A.REGDATA, 0xFF);
    writeReg(BANK_A.REGPULLUP, 0x00);
    writeReg(BANK_A.REGPULLDN, 0x00);
    writeReg(BANK_A.REGINTMASK, 0xFF);
    writeReg(BANK_A.REGSNSHI, 0x00);
    writeReg(BANK_A.REGSNSLO, 0x00);

    writeReg(BANK_B.REGDIR, 0xFF);
    writeReg(BANK_B.REGDATA, 0xFF);
    writeReg(BANK_B.REGPULLUP, 0x00);
    writeReg(BANK_B.REGPULLDN, 0x00);
    writeReg(BANK_A.REGINTMASK, 0xFF);
    writeReg(BANK_B.REGSNSHI, 0x00);
    writeReg(BANK_B.REGSNSLO, 0x00);
  }

  //***********************************************************************
  //
  // Returns the register numbers for the bank that the given gpio is on
  function bank(gpio){
    return (gpio > 7) ? BANK_B : BANK_A;
  }

  //***********************************************************************
  //
  // configure whether edges trigger an interrupt for specified GPIO
  function setIrqEdges( gpio, rising, falling) {
    local bank = bank(gpio);
    gpio = gpio % 8;
    local mask = 0x03 << ((gpio & 3) << 1);
    local data = (2*falling + rising) << ((gpio & 3) << 1);
    writeMasked(gpio >= 4 ? bank.REGSNSHI : bank.REGSNSLO, data, mask);
  }

  //***********************************************************************
  //
  // Resets all the IRQs
  function clearAllIrqs() {
    writeReg(BANK_A.REGINTSRC,0xff);
    writeReg(BANK_B.REGINTSRC,0xff);
  }

  //***********************************************************************
  //
  // Read all the IRQs as a single 16-bit bitmap
  function getIrq(){
    return ((readReg(BANK_B.REGINTSRC) & 0xFF) << 8) | (readReg(BANK_A.REGINTSRC) & 0xFF);
  }

  //***********************************************************************
  //
  // sets the clock
  function setClock(gpio, enable) {
    writeReg(bank(gpio).REGCLOCK, enable ? 0x50 : 0x00); // 2mhz internal oscillator
  }

  //***********************************************************************
  //
  // enable or disable the LED drivers
  function setLEDDriver(gpio, enable) {
    writeBit(bank(gpio).REGLEDDRV, gpio & 7, enable ? 1 : 0);
    writeReg(bank(gpio).REGMISC, 0x70); // Set clock to 2mhz / (2 ^ (1-1)) = 2mhz, use linear fading
  }

  //***********************************************************************
  //
  // sets the Time On value for the LED register
  function setTimeOn(gpio, value) {
    writeReg(gpio<4 ? 0x29+gpio*3 : 0x35+(gpio-4)*5, value)
      }

  //***********************************************************************
  //
  // sets the On Intensity level LED register
  function setIntensityOn(gpio, value) {
    writeReg(gpio<4 ? 0x2A+gpio*3 : 0x36+(gpio-4)*5, value)
      }

  //***********************************************************************
  //
  // sets the Time Off value for the LED register
  function setOff(gpio, value) {
    writeReg(gpio<4 ? 0x2B+gpio*3 : 0x37+(gpio-4)*5, value)
      }

  //***********************************************************************
  //
  // sets the Rise Time value for the LED register
  function setRiseTime(gpio, value) {
    if (gpio % 8 < 4) return; // Can't do all pins
    writeReg(gpio<12 ? 0x38+(gpio-4)*5 : 0x58+(gpio-12)*5, value)
      }

  //***********************************************************************
  //
  // sets the Fall Time value for the LED register
  function setFallTime(gpio, value) {
    if (gpio % 8 < 4) return; // Can't do all pins
    writeReg(gpio<12 ? 0x39+(gpio-4)*5 : 0x59+(gpio-12)*5, value)
      }
};

//****************************************************************************
//
// This is a convenience class that simplifies the configuration of a
// IO Expander GPIO port.  You can use it in a similar manner to
// hardware.pin with two main differences:
//
// 1. There is a new pin type: LED_OUT, for controlling LED brightness
// (basically PWM_OUT with "breathing")
//
// 2. The pin events will include the pin state as the one parameter
// to the callback
//
class ExpGPIO {
  _expander = null;  //Instance of an Expander class
  _gpio     = null;  //Pin number of this GPIO pin
  _mode     = null;  //The mode configured for this pin

  // This definition augments the pin configuration constants as defined in:
  // http://electricimp.com/docs/api/hardware/pin/configure/
  //
  static LED_OUT = 1000001;

  // Constructor requires the IO Expander class and the pin number to aquire
  //
  constructor(expander, gpio) {
    _expander = expander;
    _gpio     = gpio;
  }

  //***********************************************************************
  //
  // Optional initial state (defaults to 0 just like the imp)
  function configure(mode, param = null) {
    _mode = mode;

    if (mode == DIGITAL_OUT) {
      // Digital out - Param is the initial value of the pin
      // Set the direction, turn off the pull up and enable the pin
      _expander.setDir(_gpio,1);
      _expander.setPullUp(_gpio,0);
      if(param != null) {
        _expander.setPin(_gpio, param);
      } else {
        _expander.setPin(_gpio, 0);
      }

      return this;
    } else if (mode == ExpGPIO.LED_OUT) {
      // LED out - Param is the initial intensity
      // Set the direction, turn off the pull up and enable the pin
      // Configure a bunch of other LED specific timers and settings
      _expander.setPullUp(_gpio, 0);
      _expander.setInputBuffer(_gpio, 0);
      _expander.setOpenDrain(_gpio, 1);
      _expander.setDir(_gpio, 1);
      _expander.setClock(_gpio, 1);
      _expander.setLEDDriver(_gpio, 1);
      _expander.setTimeOn(_gpio, 0);
      _expander.setOff(_gpio, 0);
      _expander.setRiseTime(_gpio, 0);
      _expander.setFallTime(_gpio, 0);
      _expander.setIntensityOn(_gpio, param > 0 ? param : 0);
      _expander.setPin(_gpio, param > 0 ? 0 : 1);

      return this;
    } else if (mode == DIGITAL_IN) {
      // Digital in - Param is the callback function
      // Set the direction and disable to pullup
      _expander.setDir(_gpio,0);
      _expander.setPullUp(_gpio,0);
      // Fall through to the callback setup
    } else if (mode == DIGITAL_IN_PULLUP) {
      // Param is the callback function
      // Set the direction and turn on the pullup
      _expander.setDir(_gpio,0);
      _expander.setPullUp(_gpio,1);
      // Fall through to the callback setup
    }

    if (typeof param == "function") {
      // If we have a callback, configure it against a rising IRQ edge
      _expander.setIrqMask(_gpio,1);
      _expander.setIrqEdges(_gpio,1,1);
      _expander.setCallback(_gpio, param);
    } else {
      // Disable the callback for this pin
      _expander.setIrqMask(_gpio,0);
      _expander.setIrqEdges(_gpio,0,0);
      _expander.setCallback(_gpio,null);
    }

    return this;
  }

  //***********************************************************************
  //
  // Reads the stats of the configured pin
  function read() {
    return _expander.getPin(_gpio);
  }

  //***********************************************************************
  //
  // Sets the state of the configured pin
  function write(state) {
    _expander.setPin(_gpio,state);
  }

  //***********************************************************************
  //
  // Set the intensity of an LED OUT pin. Don't use for other pin types.
  function setIntensity(intensity) {
    _expander.setIntensityOn(_gpio,intensity);
  }

  //***********************************************************************
  //
  // Set the blink rate of an LED OUT pin. Don't use for other pin types.
  function blink(rampup, rampdown, intensityon, intensityoff = 0, fade=true) {
    rampup = (rampup > 0x1F ? 0x1F : rampup);
    rampdown = (rampdown > 0x1F ? 0x1F : rampdown);
    intensityon = intensityon & 0xFF;
    intensityoff = (intensityoff > 0x07 ? 0x07 : intensityoff);

    _expander.setTimeOn(_gpio, rampup);
    _expander.setOff(_gpio, rampdown << 3 | intensityoff);
    _expander.setRiseTime(_gpio, fade?5:0);
    _expander.setFallTime(_gpio, fade?5:0);
    _expander.setIntensityOn(_gpio, intensityon);
    _expander.setPin(_gpio, intensityon>0 ? 0 : 1)
      }

  //***********************************************************************
  //
  // Enable or disable fading (breathing)
  function fade(on, risetime = 5, falltime = 5) {
    _expander.setRiseTime(_gpio, on ? risetime : 0);
    _expander.setFallTime(_gpio, on ? falltime : 0);
  }
};

//****************************************************************************
//
// A random floating point number between 0 and 1.
local mrand = math.rand.bindenv(math);

function random() {
  return 1.0 * mrand() / RAND_MAX;
}

//****************************************************************************
//
// write the color specified by 'r,g,b' to the output stream (a blob())
//
function write_color(out, r, g, b) {
  out.writen(r, 'b');
  out.writen(g, 'b');
  out.writen(b, 'b');
  return out;
};

//****************************************************************************
//
// Given a position on the color wheel, write it to our output stream
// ('out' is a blob())
//
function write_from_color_wheel(out, wheel_pos) {
  if (wheel_pos < 85) {
    return write_color(out, wheel_pos * 3, 255 - wheel_pos * 3, 0);
  }
  else if (wheel_pos < 170)   {
    wheel_pos -= 85;
    return write_color(out, 255 - wheel_pos * 3, 0, wheel_pos * 3);
  } else {
    wheel_pos -= 170;
    return write_color(out, 0, wheel_pos * 3, 255 - wheel_pos * 3);
  }
};

//****************************************************************************
//
// This class wraps all of the work interfacing with the switches and
// other stuff related to controlling the christmas tree star. The
// rotating switch and anything else we add. It nicely figures out the
// state of things and exports that for other parts of the system to
// query or set.
//
// NOTE: Right now this is just the rotary switch.. but in the future
// this is where the light and temperature sensor would go, and the
// interface to the music player if we were to add one of those.
//
class StarController {
  i2c = null;
  ioexp = null;
  star_lights = null;

  // The rotary switch has a 4 bit binary ouptut. We store the
  // composite output whenever it changes. We see it as four
  // buttons.
  //
  rotary_0 = null;
  rotary_1 = null;
  rotary_2 = null;
  rotary_3 = null;
  curr_value = null;

  //***********************************************************************
  //
  constructor(sl) {
    star_lights = sl;

    // Initialize the I2C bus
    //
    i2c = hardware.i2c89;
    i2c.configure(CLOCK_SPEED_400_KHZ);

    // Initialize IO expander
    //
    ioexp = SX1509(i2c, 0x7C, hardware.pin1);

    // The four contacts for the 16 position binary rotary switch
    // are attached to pins 0-3.
    //
    rotary_0 = ExpGPIO(ioexp, 0).configure(DIGITAL_IN_PULLUP);
    rotary_1 = ExpGPIO(ioexp, 1).configure(DIGITAL_IN_PULLUP);
    rotary_2 = ExpGPIO(ioexp, 2).configure(DIGITAL_IN_PULLUP);
    rotary_3 = ExpGPIO(ioexp, 3).configure(DIGITAL_IN_PULLUP);
    curr_value = rotary_position();
    star_lights.set_animation(curr_value);
    server.log(format("Rotary switch position now: %d", curr_value));
  }

  //***********************************************************************
  //
  // Return the position of the rotary switch as a value between 0 and 15.
  //
  function rotary_position() {
    return (rotary_3.read() << 3) + (rotary_2.read() << 2) +
      (rotary_1.read() << 1) + rotary_0.read();
  }

  //****************************************************************************
  //
  // Every second probe the rotary switch and log its values
  //
  function rotary_probe() {
    imp.wakeup(1.0, rotary_probe.bindenv(this));
    local rotary_pos = rotary_position();
    if (rotary_pos != curr_value) {
      curr_value = rotary_pos;
      star_lights.set_animation(curr_value);
      server.log(format("Rotary switch position now: %d", curr_value));
    }
  }
};

//****************************************************************************
//
class Animation {

  name = null;

  // This variable will be assigned a table in the class's
  // constructor that can be used by the animation function to hold
  // bits of state unique to this instance of this animation.
  //
  state = null;

  // how long do we sleep between frames? (in seconds)
  //
  inter_frame_wait = null;

  // How many frames are in this animation?
  //
  num_frames = null;

  // How many pixels do we actually have to work with..
  //
  _num_pixels = null;

  //***********************************************************************
  //
  constructor(num_pixels) {
    state = {};
    _num_pixels = num_pixels;
    inter_frame_wait = 0.1;
  }

  //***********************************************************************
  //
  // Run the animation for one frame. Passed in is the animation frame
  // number (because the StarLights object has to keep track of when
  // to do things like change animations), and the spi devices to
  // write our animation frame out to.
  //
  // This must be overridden in subclasses
  //
  function one_frame(frame_num, out) {
    if (frame_num == 0) {
      init_animation(out)
    }
  }

  //***********************************************************************
  //
  // This function is called by one_frame() if one_frame() is called
  // with a frame_num == 0. Lets us do any setup necessary for the
  // state of this animation based on its intended starting state.
  //
  // This must be overridden in subclasses
  //
  function init_animation(out) {
  }
};

//****************************************************************************
//
class PointRainbow extends Animation {

  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = 256;
    inter_frame_wait = 0.005;
    name = "PointRainbow";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this

    for (local i=0; i < _num_pixels; ++i) {
      out = write_from_color_wheel(out,
                                   ((i * 256 / _num_pixels) + frame_num) % 256);
    }
    return out;
  }
};

//****************************************************************************
//
class Rainbow extends Animation {

  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = 256;
    inter_frame_wait = 0.1;
    name = "Rainbow";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this
    for (local i=0; i<_num_pixels; ++i) {
      out = write_from_color_wheel( out, (i + frame_num) % 255);
    }
    return out;
  }
};

//****************************************************************************
//
class Wipe extends Animation {

  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = num_pixels;
    inter_frame_wait = 0.03;
    name = "Wipe";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this
    for (local i=0; i<_num_pixels; ++i) {
      if (i == frame_num) {
        out = write_color(out, 255, 255, 255);
      } else {
        out = write_color(out, 0, 0, 0);
      }
    }
    return out;
  }
};

//****************************************************************************
//
class SlowInOrder extends Animation {

  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = num_pixels;
    inter_frame_wait = 1;
    name = "SlowInOrder";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this
    for (local i=0; i<_num_pixels; ++i) {
      if (i == frame_num) {
        out = write_color(out, 255, 255, 255);
      } else {
        out = write_color(out, 0, 0, 0);
      }
    }
    return out;
  }
};

//****************************************************************************
//
class Sparkle extends Animation {

  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = num_pixels;
    inter_frame_wait = 0.05;
    name = "Sparkle";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this
    for (local i=0; i<_num_pixels; ++i) {
      if (frame_num % 3 == 0) {
        if (random() < 0.2) {
          out = write_color(out, 255, 255, 255);
        } else {
          out = write_color(out, 0, 0, 0);
        }
      } else {
          out = write_color(out, 0, 0, 0);
      }
    }
    return out;
  }
}

//****************************************************************************
//
class NightSnow extends Animation {
  //***********************************************************************
  //
  constructor(num_pixels) {
    base.constructor(num_pixels);
    num_frames = num_pixels;
    inter_frame_wait = 0.05;
    name = "NightSnow";
  }

  //***********************************************************************
  //
  function one_frame(frame_num, out) {
    base.one_frame(frame_num, out);  // There is nothing to init so we
                                     // could skip this
    for (local i=0; i<_num_pixels; ++i) {
      if (i == _num_pixels-1) {
        out = write_color(out, 50, 50, 50);
      } else {
        out = write_color(out, 0, 0, 10);
      }
    }
    return out;
  }
}

//****************************************************************************
//
// I thought about naming this class 'StartLight' 'cause that sounds a
// bit cooler.. but this is the interface to the 12 star lights.. one
// for each point of the star.
//
class StarLights {

  spi = null;

  // What pattern to play on our star lights. We only accept 0-15
  //
  curr_anim_idx = 0;
  curr_anim = null;

  // We have a stack of animations that we want to play in order. As
  // long as this array is non-empty when the current animation
  // finishes its run we will switch to the next animation.
  //
  // NOTE: Unless the 'immediate' flag is set, then that means
  // switch to the next animation immediately (which also clears the
  // 'immediate' flag. This lets us switch to a new animation while
  // in the middle of a long running animation.
  //
  next_animation = null;
  immediately = null;

  // This will hold the array of animations (note: this is shared
  // with all instances of this class.. but that is fine)
  //
  animations = null;
  num_animations = null;

  // The 'wipe' animation is used between animations.. mostly as a
  // way to visually signal that we are changing to the next
  // animation due to a command.
  //
  wipe_animation = null;

  // The 'frame' is the clock that drives the animations. As we run
  // the animation we call the animation passing in the 'frame'
  // count. After the animation does its one frame run, we increment
  // the frame count. If the frame count now exceeds the number of
  // frames in the animation, we reset the frame count to zero.
  //
  // NOTE: The number of frames in an animation comes from the
  // animation instance itself.
  //
  frame = 0;

  static NUM_PIXELS = 12;

  //***********************************************************************
  //
  // For all the work of talking to the WS2801 chain of LED's I am
  // just copy and pasting code with modifications. Not really
  // bothering to grok the protocol or the why of it (until it stops
  // working and forces me to learn how it is supposed to work)
  //
  constructor(initial_animation = 0) {

    wipe_animation = Wipe(NUM_PIXELS);
    animations = [ PointRainbow(NUM_PIXELS),
                   Rainbow(NUM_PIXELS),
                   Sparkle(NUM_PIXELS),
                   NightSnow(NUM_PIXELS),
                   SlowInOrder(NUM_PIXELS),
                   ];
    num_animations = animations.len();

    server.log("Starting up with Wipe animation");

    // When we start we will do a wipe and the initial animation.
    //
    immediately = false;
    curr_anim = wipe_animation;
    next_animation = [];
    next_animation.append(animations[initial_animation]);
    curr_anim_idx = initial_animation;

    // Basically we are jumping on top of the SPI bus to write to
    // our WS2801 star lights. This sets up the bus for all of our
    // magic. Right now we are hard coding for using spi257.
    //
    server.log("spi config start");
    spi = hardware.spi257;
    spi.configure(SIMPLEX_TX, 15000); // Datasheet says max 25MHz

    // We clock pin5 up down and then up I think to reset the
    // entire WS2801 bus.
    //
    hardware.pin5.configure(DIGITAL_OUT);
    hardware.pin5.write(0);
    imp.sleep(0.01);
    hardware.pin5.write(1);
    hardware.configure(SPI_257);
    server.log("spi config end");
  }

  //***********************************************************************
  //
  // Set the animation to the given one.. if the number is outside the
  // range for the animations we have, then set it to animation 0.
  //
  // XXX We need to choose how we are indicating the animations.. an
  //     index in to animations[] or an Animation instance.
  //
  function set_animation(which) {
    if (which >= num_animations) {
      which = 0;
    }
    next_animation.append(wipe_animation);
    next_animation.append(animations[which]);
    immediately = true;
  }

  //***********************************************************************
  //
  // This will run the animation in a loop.  At the start it
  // determines what animation we are running, and based on the
  // frame do that animation.
  //
  function run_animation() {

    // Calculate our wakeup delay. It must be no greater than 0.4
    // seconds.  This is to make sure that a long animation does not
    // starve us watching for interrupts or network traffic.
    //
    local wakeup_delay = curr_anim.num_frames * curr_anim.inter_frame_wait;
    if (wakeup_delay >= 0.4) {
      wakeup_delay = 0.4;
    }

    // Based on how long we are going to run this animation before we
    // exit setup the re-invocation of this function to be right as we
    // finish the running through the correct number of frames for
    // this run.
    //
    local frames_this_run = wakeup_delay / curr_anim.inter_frame_wait;
    if (frames_this_run > (curr_anim.num_frames - frame)) {
      frames_this_run = curr_anim.num_frames - frame;
    }
    local wakeup_time = curr_anim.inter_frame_wait * frames_this_run;
    local timer = imp.wakeup(wakeup_time, run_animation.bindenv(this));

    // Run the animation for 'frames_this_run' frames (or until we
    // have hit the number of frames in this animation.)
    //
    for (local i = 0;
         i < frames_this_run && frame < curr_anim.num_frames;
         i++, frame++) {
      local out = blob(3*NUM_PIXELS);
      out = curr_anim.one_frame(frame, out);
      spi.write(out);
      imp.sleep(curr_anim.inter_frame_wait);

      // If while we were sleeping 'immediately' got set to true then
      // we basically received an interrupt to stop this animation and
      // move on to the next one. So, we cancel the existing wakeup
      // timer and make a new one to run as soon as the imp is
      // idle. We set 'frame' to be 0 to force us to load the next
      // animation if there is one.
      //
      if (immediately == true) {
        immediately = false;
        imp.cancelwakeup(timer);
        imp.wakeup(0.0, run_animation.bindenv(this));
        frame = 0;
        break;
      }
    }

    // If we have run through all of the frames in this animation,
    // then start the animation over at its beginning.
    //
    if (frame >= curr_anim.num_frames) {
      frame = 0;
    }

    // If we have other animations in the queue to be run, then set
    // the next animation to run next (removing it from the queue)
    //
    if (frame == 0 && next_animation.len() > 0) {
        curr_anim = next_animation[0];
        next_animation.remove(0);
        server.log("Starting animation " + curr_anim.name);
    }
  }
};

//****************************************************************************
//
// Setup for handling disconnection from the wifi network.
// This function is called if the agent link is lost.
//
function disconnection_handler(reason) {
  if (reason != SERVER_CONNECTED) {
    disconnected_flag = true;
  } else {
    server.log("Reconnected!");
  }
};

//****************************************************************************
//
function reconnect_loop() {
  reconnect_timer = imp.wakeup(10.0, reconnect_loop);

  // If we are disconnected, every 15 minutes attempt to reconnect
  //
  if (disconnected_flag) {
    disconnected_count++;

    if (disconnected_count > 90) {
      // main_program_loop() iterates every second, so count the
      // iterations until we have had 15 minutes’ worth then try
      // to reconnect
      //
      disconnected_flag = false;
      disconnected_count = 0;
      server.connect(disconnection_handler, 30.0);
    }
  }
};

//##########################################################################
//
function main() {
  local star_lights = StarLights(0);
  local star_controller = StarController(star_lights);
  star_controller.rotary_probe();
  star_lights.run_animation();
}

// Start of program
reconnect_timer <- null;
disconnected_flag <- false;
disconnected_count <- 0;

server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 30.0);
server.onunexpecteddisconnect(disconnection_handler);

bullwinkle <- Bullwinkle();
bullwinkle.set_timeout(5);
bullwinkle.set_retries(3);

// This starts the ball rolling..
//
reconnect_loop();
main();
