/*global cordova*/
module.exports = {

    connect: function (macAddress, success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "connect", [macAddress]);
    },

    disconnect: function (macAddress, success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "disconnect", [macAddress]);
    },

    // list bound devices
    list: function (success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "list", []);
    },

    isEnabled: function (success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "isEnabled", []);
    },

    // writes data to the bluetooth serial port
    // data can be an ArrayBuffer, string, integer array, or Uint8Array
    write: function (macAddress, data, success, failure) {

        // convert to ArrayBuffer
        if (typeof data === 'string') {
            data = stringToArrayBuffer(data);
        } else if (data instanceof Array) {
            // assuming array of interger
            data = new Uint8Array(data).buffer;
        } else if (data instanceof Uint8Array) {
            data = data.buffer;
        }

        cordova.exec(success, failure, "BluetoothSerial", "write", [macAddress, data]);
    },

    // calls the success callback when new data is available
    subscribe: function (macAddress, delimiter, success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "subscribe", [macAddress, delimiter]);
    },

    // removes data subscription
    unsubscribe: function (macAddress, success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "unsubscribe", [macAddress]);
    },

    // calls the success callback when new data is available with an ArrayBuffer
    subscribeRawData: function (macAddress, success, failure) {
        successWrapper = function(data) {
            // Windows Phone flattens an array of one into a number which
            // breaks the API. Stuff it back into an ArrayBuffer.
            if (typeof data === 'number') {
                var a = new Uint8Array(1);
                a[0] = data;
                data = a.buffer;
            }
            success(data);
        };
        cordova.exec(successWrapper, failure, "BluetoothSerial", "subscribeRaw", [macAddress]);
    },

    // removes data subscription
    unsubscribeRawData: function (macAddress, success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "unsubscribeRaw", [macAddress]);
    },

    enable: function (success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "enable", []);
    },

    discoverUnpaired: function (success, failure) {
        cordova.exec(success, failure, "BluetoothSerial", "discoverUnpaired", []);
    },

    setDeviceDiscoveredListener: function (notify) {
        if (typeof notify != 'function')
            throw 'BluetoothSerial.setDeviceDiscoveredListener: Callback not a function'

        cordova.exec(notify, null, "BluetoothSerial", "setDeviceDiscoveredListener", []);
    },

    clearDeviceDiscoveredListener: function () {
        cordova.exec(null, null, "BluetoothSerial", "clearDeviceDiscoveredListener", []);
    }

};

var stringToArrayBuffer = function(str) {
    var ret = new Uint8Array(str.length);
    for (var i = 0; i < str.length; i++) {
        ret[i] = str.charCodeAt(i);
    }
    return ret.buffer;
};
