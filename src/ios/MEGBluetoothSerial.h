//
//  MEGBluetoothSerial.h
//  Bluetooth Serial Cordova Plugin
//
//  Created by Don Coleman on 5/21/13.
//
//

#ifndef SimpleSerial_MEGBluetoothSerial_h
#define SimpleSerial_MEGBluetoothSerial_h

#import <Cordova/CDV.h>
#import "BLE.h"

@interface MEGBluetoothSerial : CDVPlugin <BLEDelegate> {
    BLE *_bleShield;
    NSMutableDictionary* _connectCallbackIds; // connecting callbacks, device id as a key
    NSMutableDictionary* _subscribeCallbackIds; // subscribe callbacks, device id as a key
    NSString* _subscribeBytesCallbackId;
    NSString* _rssiCallbackId;
    NSMutableString *_buffer;
    NSMutableDictionary* _delimiters;  // message delimiters for different devices, device id as a key
}

- (void)connect:(CDVInvokedUrlCommand *)command;
- (void)disconnect:(CDVInvokedUrlCommand *)command;

- (void)subscribe:(CDVInvokedUrlCommand *)command;
- (void)unsubscribe:(CDVInvokedUrlCommand *)command;
- (void)subscribeRaw:(CDVInvokedUrlCommand *)command;
- (void)unsubscribeRaw:(CDVInvokedUrlCommand *)command;
- (void)write:(CDVInvokedUrlCommand *)command;

- (void)list:(CDVInvokedUrlCommand *)command;
- (void)isEnabled:(CDVInvokedUrlCommand *)command;

- (void)available:(CDVInvokedUrlCommand *)command;

@end

#endif
