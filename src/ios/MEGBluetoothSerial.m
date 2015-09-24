//
//  MEGBluetoothSerial.m
//  Bluetooth Serial Cordova Plugin
//
//  Created by Don Coleman on 5/21/13.
//
//

#import "MEGBluetoothSerial.h"
#import <Cordova/CDV.h>

@interface MEGBluetoothSerial()
- (NSString *)readUntilDelimiter:(NSString *)delimiter;
- (NSMutableArray *)getPeripheralList;
- (void)sendDataToSubscriber;
- (CBPeripheral *)findPeripheralByUUID:(NSString *)uuid;
- (void)connectToUUID:(NSString *)uuid;
- (void)listPeripheralsTimer:(NSTimer *)timer;
- (void)connectFirstDeviceTimer:(NSTimer *)timer;
- (void)connectUuidTimer:(NSTimer *)timer;
@end

@implementation MEGBluetoothSerial

- (void)pluginInitialize {

    NSLog(@"Bluetooth Serial Cordova Plugin - BLE version");
    NSLog(@"(c)2013-2014 Don Coleman");

    [super pluginInitialize];

    _bleShield = [[BLE alloc] init];
    [_bleShield controlSetup];
    [_bleShield setDelegate:self];

    _buffer = [[NSMutableString alloc] init];
    _connectCallbackIds = [NSMutableDictionary dictionary];
}

#pragma mark - Cordova Plugin Methods

- (void)connect:(CDVInvokedUrlCommand *)command {

    NSLog(@"connect");
    NSString *uuid = [command.arguments objectAtIndex:0];

    // if the uuid is null or blank, scan and
    // connect to the first available device

    if (uuid == (NSString*)[NSNull null]) {
        [self connectToFirstDevice];
    } else if ([uuid isEqualToString:@""]) {
        [self connectToFirstDevice];
    } else {
        [self connectToUUID:uuid];
    }

    [_connectCallbackIds setObject:[command.callbackId copy] forKey:uuid];
}

- (void)disconnect:(CDVInvokedUrlCommand*)command {

    NSLog(@"disconnect");
    NSString *uuid = [command.arguments objectAtIndex:0];

    [_connectCallbackIds removeObjectForKey:uuid];
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];

    CBPeripheral* peripheral = [_bleShield activePeripheralForUuid:uuid];
    if (peripheral) {
        if(peripheral.state == CBPeripheralStateConnected)
        {
            [[_bleShield CM] cancelPeripheralConnection:peripheral];
        }
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)subscribe:(CDVInvokedUrlCommand*)command {
    NSLog(@"subscribe");
    NSString *uuid = [command.arguments objectAtIndex:0];

    CDVPluginResult *pluginResult = nil;
    NSString *delimiter = [command.arguments objectAtIndex:1];

    if (delimiter != nil) {
        if (!_subscribeCallbackIds) {
            _subscribeCallbackIds = [NSMutableDictionary dictionary];
        }
        [_subscribeCallbackIds setObject:[command.callbackId copy] forKey:uuid];

        if (!_delimiters) {
            _delimiters = [NSMutableDictionary dictionary];
        }

        [_delimiters setObject:[delimiter copy] forKey:uuid];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"delimiter was null"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)unsubscribe:(CDVInvokedUrlCommand*)command {
    NSLog(@"unsubscribe");
    NSString *uuid = [command.arguments objectAtIndex:0];

    [_delimiters removeObjectForKey:uuid];
    [_subscribeCallbackIds removeObjectForKey:uuid];

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)subscribeRaw:(CDVInvokedUrlCommand*)command {
    NSLog(@"subscribeRaw");

    _subscribeBytesCallbackId = [command.callbackId copy];
}

- (void)unsubscribeRaw:(CDVInvokedUrlCommand*)command {
    NSLog(@"unsubscribeRaw");

    _subscribeBytesCallbackId = nil;

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)write:(CDVInvokedUrlCommand*)command {
    NSLog(@"write");

    CDVPluginResult *pluginResult = nil;
    NSString *uuid = [command.arguments objectAtIndex:0];
    NSData *data  = [command.arguments objectAtIndex:1];

    if (data != nil) {

        [_bleShield write:uuid data:data];

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"data was null"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)list:(CDVInvokedUrlCommand*)command {

    [self scanForBLEPeripherals:3];

    [NSTimer scheduledTimerWithTimeInterval:(float)3.0
                                     target:self
                                   selector:@selector(listPeripheralsTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];
}

- (void)discoverUnpaired:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                        messageAsInt:0];
    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)isEnabled:(CDVInvokedUrlCommand*)command {

    // short delay so CBCentralManger can spin up bluetooth
    [NSTimer scheduledTimerWithTimeInterval:(float)0.2
                                     target:self
                                   selector:@selector(bluetoothStateTimer:)
                                   userInfo:[command.callbackId copy]
                                    repeats:NO];

}

- (void)available:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:[_buffer length]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}
#pragma mark - BLEDelegate

- (void)bleDidReceiveData:uuid data:(unsigned char *)data length:(int)length {
    NSLog(@"bleDidReceiveData");

    // Append to the buffer
    NSData *d = [NSData dataWithBytes:data length:length];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    NSLog(@"Received %@", s);

    if (s) {
        [_buffer appendString:s];
        [self sendDataToSubscriber:uuid]; // only sends if a delimiter is hit

    } else {
        NSLog(@"Error converting received data into a String.");
    }

    // Always send raw data if someone is listening
    if (_subscribeBytesCallbackId) {
        NSData* nsData = [NSData dataWithBytes:(const void *)data length:length];
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:nsData];
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_subscribeBytesCallbackId];
    }

}

- (void)bleDidConnect:(NSString*) uuid {
    NSLog(@"bleDidConnect");
    CDVPluginResult *pluginResult = nil;

    NSString* connectCallbackId = [_connectCallbackIds objectForKey:uuid];
    if (connectCallbackId) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
    }
}

- (void)bleDidDisconnect:(NSString*) uuid {
    // TODO is there anyway to figure out why we disconnected?
    NSLog(@"bleDidDisconnect");

    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Disconnected"];
    NSString* connectCallbackId = [_connectCallbackIds objectForKey:uuid];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];

    [_connectCallbackIds removeObjectForKey:uuid];
}

- (void)bleDidUpdateRSSI:(NSNumber *)rssi {
    if (_rssiCallbackId) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[rssi doubleValue]];
        [pluginResult setKeepCallbackAsBool:TRUE]; // TODO let expire, unless watching RSSI
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_rssiCallbackId];
    }
}

#pragma mark - timers

-(void)listPeripheralsTimer:(NSTimer *)timer {
    NSString *callbackId = [timer userInfo];
    NSMutableArray *peripherals = [self getPeripheralList];

    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray: peripherals];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

-(void)connectFirstDeviceTimer:(NSTimer *)timer {
    NSString *uuid = [timer userInfo];

    if(_bleShield.peripherals.count > 0) {
        NSLog(@"Connecting");
        [_bleShield connectPeripheral:[_bleShield.peripherals objectAtIndex:0]];
    } else {
        NSString *error = @"Did not find any BLE peripherals";
        NSLog(@"%@", error);

        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:[_connectCallbackIds objectForKey:uuid]];
    }
}

-(void)connectUuidTimer:(NSTimer *)timer {

    NSString *uuid = [timer userInfo];

    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];

    if (peripheral) {
        [_bleShield connectPeripheral:peripheral];
    } else {
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];

        [self.commandDelegate sendPluginResult:pluginResult
                                    callbackId:[_connectCallbackIds objectForKey:uuid]];
    }
}

- (void)bluetoothStateTimer:(NSTimer *)timer {

    NSString *callbackId = [timer userInfo];
    CDVPluginResult *pluginResult = nil;

    int bluetoothState = [[_bleShield CM] state];

    BOOL enabled = bluetoothState == CBCentralManagerStatePoweredOn;

    if (enabled) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:bluetoothState];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

#pragma mark - internal implemetation

- (NSString*)readUntilDelimiter: (NSString*) delimiter {
    if (!delimiter) {
        return @"";
    }

    NSRange range = [_buffer rangeOfString: delimiter];
    NSString *message = @"";

    if (range.location != NSNotFound) {

        int end = range.location + range.length;
        message = [_buffer substringToIndex:end];

        NSRange truncate = NSMakeRange(0, end);
        [_buffer deleteCharactersInRange:truncate];
    }
    return message;
}

- (NSMutableArray*) getPeripheralList {

    NSMutableArray *peripherals = [NSMutableArray array];

    for (int i = 0; i < _bleShield.peripherals.count; i++) {
        NSMutableDictionary *peripheral = [NSMutableDictionary dictionary];
        CBPeripheral *p = [_bleShield.peripherals objectAtIndex:i];

        NSString *uuid = p.identifier.UUIDString;
        [peripheral setObject: uuid forKey: @"uuid"];
        [peripheral setObject: uuid forKey: @"id"];

        NSString *name = [p name];
        if (!name) {
            name = [peripheral objectForKey:@"uuid"];
        }
        [peripheral setObject: name forKey: @"name"];

        NSNumber *rssi = [p advertisementRSSI];
        if (rssi) { // BLEShield doesn't provide advertised RSSI
            [peripheral setObject: rssi forKey:@"rssi"];
        }

        [peripherals addObject:peripheral];
    }

    return peripherals;
}

// calls the JavaScript subscriber with data if we hit the _delimiter
- (void) sendDataToSubscriber:(NSString *)uuid {
    NSString *delimiter = [_delimiters objectForKey:uuid];
    if (!delimiter) {
        return;
    }

    NSString *message = [self readUntilDelimiter:delimiter];

    if ([message length] > 0) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: message];
        [pluginResult setKeepCallbackAsBool:TRUE];
        NSString* callbackId = [_subscribeCallbackIds objectForKey:uuid];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
        [self sendDataToSubscriber:uuid];
    }

}

// Ideally we'd get a callback when found, maybe _bleShield can be modified
// to callback on centralManager:didRetrievePeripherals. For now, use a timer.
- (void)scanForBLEPeripherals:(int)timeout {

    NSLog(@"Scanning for BLE Peripherals");

    // close active peripherals
    for (NSString* uuid in _bleShield.activePeripherals) {
        // disconnect
        CBPeripheral* peripheral = [_bleShield.activePeripherals objectForKey:uuid];
        if (peripheral && (peripheral.state == CBPeripheralStateConnected))
        {
            [[_bleShield CM] cancelPeripheralConnection:peripheral];
            return;
        }
    }

    // remove existing peripherals
    if (_bleShield.peripherals) {
        [_bleShield.peripherals removeAllObjects];
    }

    [_bleShield findBLEPeripherals:timeout];
}

- (void)connectToFirstDevice {

    [self scanForBLEPeripherals:3];

    [NSTimer scheduledTimerWithTimeInterval:(float)3.0
                                     target:self
                                   selector:@selector(connectFirstDeviceTimer:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)connectToUUID:(NSString *)uuid {

    int interval = 0;

    if (_bleShield.peripherals.count < 1) {
        interval = 3;
        [self scanForBLEPeripherals:interval];
    }

    [NSTimer scheduledTimerWithTimeInterval:interval
                                     target:self
                                   selector:@selector(connectUuidTimer:)
                                   userInfo:uuid
                                    repeats:NO];
}

- (CBPeripheral*)findPeripheralByUUID:(NSString*)uuid {

    NSMutableArray *peripherals = [_bleShield peripherals];
    CBPeripheral *peripheral = nil;

    for (CBPeripheral *p in peripherals) {

        NSString *other = p.identifier.UUIDString;

        if ([uuid isEqualToString:other]) {
            peripheral = p;
            break;
        }
    }
    return peripheral;
}

@end
