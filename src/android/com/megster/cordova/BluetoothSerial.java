package com.megster.cordova;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.Message;
import android.provider.Settings;
import android.util.Log;
// kludgy imports to support 2.9 and 3.0 due to package changes
import org.apache.cordova.*;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * PhoneGap Plugin for Serial Communication over Bluetooth
 */
public class BluetoothSerial extends CordovaPlugin {

    // actions
    private static final String LIST = "list";
    private static final String CONNECT = "connect";
    private static final String DISCONNECT = "disconnect";
    private static final String WRITE = "write";
    private static final String SUBSCRIBE = "subscribe";
    private static final String UNSUBSCRIBE = "unsubscribe";
    private static final String SUBSCRIBE_RAW = "subscribeRaw";
    private static final String UNSUBSCRIBE_RAW = "unsubscribeRaw";

    private static final String IS_ENABLED = "isEnabled";
    private static final String ENABLE = "enable";
    private static final String DISCOVER_UNPAIRED = "discoverUnpaired";
    private static final String SET_DEVICE_DISCOVERED_LISTENER = "setDeviceDiscoveredListener";
    private static final String CLEAR_DEVICE_DISCOVERED_LISTENER = "clearDeviceDiscoveredListener";

    // callbacks
    private HashMap<String, CallbackContext> connectCallbacks = new HashMap<String, CallbackContext>();
    private HashMap<String, CallbackContext> dataAvailableCallbacks = new HashMap<String, CallbackContext>();
    private HashMap<String, CallbackContext> dataAvailableCallbacksRaw = new HashMap<String, CallbackContext>();
    private CallbackContext enableBluetoothCallback;
    private CallbackContext deviceDiscoveredCallback;

    private BluetoothAdapter bluetoothAdapter;
    private HashMap<String, BluetoothSerialService> bluetoothSerialServices = new HashMap<String, BluetoothSerialService>();
    private HashMap<String, BluetoothSerialHandler> handlers = new HashMap<String, BluetoothSerialHandler>();

    // Debugging
    private static final String TAG = "BluetoothSerial";
    private static final boolean D = true;

    // Message types sent from the BluetoothSerialService Handler
    public static final int MESSAGE_STATE_CHANGE = 1;
    public static final int MESSAGE_READ = 2;
    public static final int MESSAGE_WRITE = 3;
    public static final int MESSAGE_DEVICE_NAME = 4;
    public static final int MESSAGE_TOAST = 5;
    public static final int MESSAGE_READ_RAW = 6;

    // Key names received from the BluetoothChatService Handler
    public static final String DEVICE_NAME = "device_name";
    public static final String TOAST = "toast";

    private static final int REQUEST_ENABLE_BLUETOOTH = 1;

    @Override
    public boolean execute(String action, CordovaArgs args, CallbackContext callbackContext) throws JSONException {

        LOG.d(TAG, "action = " + action);

        if (bluetoothAdapter == null) {
            bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        }

        boolean validAction = true;

        if (action.equals(LIST)) {

            listBondedDevices(callbackContext);

        } else if (action.equals(CONNECT)) {

            boolean secure = true;
            connect(args, secure, callbackContext);

        } else if (action.equals(DISCONNECT)) {


            final String macAddress = args.getString(0);
            connectCallbacks.remove(macAddress);
            bluetoothSerialServices.get(macAddress).stop(); // TODO check for null
            callbackContext.success();

        } else if (action.equals(WRITE)) {

            final String macAddress = args.getString(0);
            byte[] data = args.getArrayBuffer(1);
            bluetoothSerialServices.get(macAddress).write(data); // TODO check for null
            callbackContext.success();

        } else if (action.equals(SUBSCRIBE)) {
            final String macAddress = args.getString(0);
            final String delimiter = args.getString(1);
            handlers.get(macAddress).setDelimiter(delimiter);
            dataAvailableCallbacks.put(macAddress, callbackContext);

            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
            result.setKeepCallback(true);
            callbackContext.sendPluginResult(result);

        } else if (action.equals(UNSUBSCRIBE)) {

            final String macAddress = args.getString(0);

            // send no result, so Cordova won't hold onto the data available callback anymore
            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
            CallbackContext dataAvailableCallback = dataAvailableCallbacks.get(macAddress);
            dataAvailableCallback.sendPluginResult(result);
            dataAvailableCallbacks.remove(macAddress);

            callbackContext.success();

        } else if (action.equals(SUBSCRIBE_RAW)) {
            final String macAddress = args.getString(0);
            dataAvailableCallbacksRaw.put(macAddress, callbackContext);

            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
            result.setKeepCallback(true);
            callbackContext.sendPluginResult(result);

        } else if (action.equals(UNSUBSCRIBE_RAW)) {
            final String macAddress = args.getString(0);

            // send no result, so Cordova won't hold onto the data available callback anymore
            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
            CallbackContext dataAvailableCallback = dataAvailableCallbacksRaw.get(macAddress);
            dataAvailableCallback.sendPluginResult(result);
            dataAvailableCallbacksRaw.remove(macAddress);

            callbackContext.success();

        } else if (action.equals(IS_ENABLED)) {

            if (bluetoothAdapter.isEnabled()) {
                callbackContext.success();
            } else {
                callbackContext.error("Bluetooth is disabled.");
            }

        } else if (action.equals(ENABLE)) {

            enableBluetoothCallback = callbackContext;
            Intent intent = new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE);
            cordova.startActivityForResult(this, intent, REQUEST_ENABLE_BLUETOOTH);

        } else if (action.equals(DISCOVER_UNPAIRED)) {

            discoverUnpairedDevices(callbackContext);

        } else if (action.equals(SET_DEVICE_DISCOVERED_LISTENER)) {

            this.deviceDiscoveredCallback = callbackContext;

        } else if (action.equals(CLEAR_DEVICE_DISCOVERED_LISTENER)) {

            this.deviceDiscoveredCallback = null;

        } else {
            validAction = false;

        }

        return validAction;
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {

        if (requestCode == REQUEST_ENABLE_BLUETOOTH) {

            if (resultCode == Activity.RESULT_OK) {
                Log.d(TAG, "User enabled Bluetooth");
                if (enableBluetoothCallback != null) {
                    enableBluetoothCallback.success();
                }
            } else {
                Log.d(TAG, "User did *NOT* enable Bluetooth");
                if (enableBluetoothCallback != null) {
                    enableBluetoothCallback.error("User did not enable Bluetooth");
                }
            }

            enableBluetoothCallback = null;
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        for(Map.Entry<String, BluetoothSerialService> entry : bluetoothSerialServices.entrySet()) {
            BluetoothSerialService service = entry.getValue();
            if (service != null) {
                service.stop();
            }
        }
    }

    private void listBondedDevices(CallbackContext callbackContext) throws JSONException {
        JSONArray deviceList = new JSONArray();
        Set<BluetoothDevice> bondedDevices = bluetoothAdapter.getBondedDevices();

        for (BluetoothDevice device : bondedDevices) {
            deviceList.put(deviceToJSON(device));
        }
        callbackContext.success(deviceList);
    }

    private void discoverUnpairedDevices(final CallbackContext callbackContext) throws JSONException {

        final CallbackContext ddc = deviceDiscoveredCallback;

        final BroadcastReceiver discoverReceiver = new BroadcastReceiver() {

            private JSONArray unpairedDevices = new JSONArray();

            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                    BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                    try {
                        JSONObject o = deviceToJSON(device);
                        unpairedDevices.put(o);
                        if (ddc != null) {
                            PluginResult res = new PluginResult(PluginResult.Status.OK, o);
                            res.setKeepCallback(true);
                            ddc.sendPluginResult(res);
                        }
                    } catch (JSONException e) {
                        // This shouldn't happen, log and ignore
                        Log.e(TAG, "Problem converting device to JSON", e);
                    }
                } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                    callbackContext.success(unpairedDevices);
                    cordova.getActivity().unregisterReceiver(this);
                }
            }
        };

        Activity activity = cordova.getActivity();
        activity.registerReceiver(discoverReceiver, new IntentFilter(BluetoothDevice.ACTION_FOUND));
        activity.registerReceiver(discoverReceiver, new IntentFilter(BluetoothAdapter.ACTION_DISCOVERY_FINISHED));
        bluetoothAdapter.startDiscovery();
    }

    private JSONObject deviceToJSON(BluetoothDevice device) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("name", device.getName());
        json.put("address", device.getAddress());
        json.put("id", device.getAddress());
        if (device.getBluetoothClass() != null) {
            json.put("class", device.getBluetoothClass().getDeviceClass());
        }
        return json;
    }

    private void connect(CordovaArgs args, boolean secure, CallbackContext callbackContext) throws JSONException {
        String macAddress = args.getString(0);
        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(macAddress);

        if (device != null) {
            connectCallbacks.put(macAddress, callbackContext);
            BluetoothSerialHandler handler = new BluetoothSerialHandler(macAddress);
            handlers.put(macAddress, handler);

            BluetoothSerialService bluetoothSerialService = new BluetoothSerialService(handler);
            bluetoothSerialServices.put(macAddress, bluetoothSerialService);
            bluetoothSerialService.connect(device, secure);

            PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
            result.setKeepCallback(true);
            callbackContext.sendPluginResult(result);

        } else {
            callbackContext.error("Could not connect to " + macAddress);
        }
    }

    // The Handler that gets information back from the BluetoothSerialService
    // Original code used handler for the because it was talking to the UI.
    // Consider replacing with normal callbacks
    class BluetoothSerialHandler extends Handler {
        private String address;
        private StringBuffer buffer = new StringBuffer();
        private String delimiter;

        public BluetoothSerialHandler(String macAddress) {
            address = macAddress;
        }

        public void handleMessage(Message msg) {
            switch (msg.what) {
                case MESSAGE_READ:
                    buffer.append((String)msg.obj);
                    sendDataToSubscriber();
                    break;
                case MESSAGE_READ_RAW:
                    byte[] bytes = (byte[]) msg.obj;
                    sendRawDataToSubscriber(bytes);
                    break;
                case MESSAGE_STATE_CHANGE:

                    if(D) Log.i(TAG, "MESSAGE_STATE_CHANGE: " + msg.arg1);
                    switch (msg.arg1) {
                        case BluetoothSerialService.STATE_CONNECTED:
                            Log.i(TAG, "BluetoothSerialService.STATE_CONNECTED");
                            notifyConnectionSuccess(address);
                            break;
                        case BluetoothSerialService.STATE_CONNECTING:
                            Log.i(TAG, "BluetoothSerialService.STATE_CONNECTING");
                            break;
                        case BluetoothSerialService.STATE_LISTEN:
                            Log.i(TAG, "BluetoothSerialService.STATE_LISTEN");
                            break;
                        case BluetoothSerialService.STATE_NONE:
                            Log.i(TAG, "BluetoothSerialService.STATE_NONE");
                            break;
                    }
                    break;
                case MESSAGE_WRITE:
                    //  byte[] writeBuf = (byte[]) msg.obj;
                    //  String writeMessage = new String(writeBuf);
                    //  Log.i(TAG, "Wrote: " + writeMessage);
                    break;
                case MESSAGE_DEVICE_NAME:
                    Log.i(TAG, msg.getData().getString(DEVICE_NAME));
                    break;
                case MESSAGE_TOAST:
                    String message = msg.getData().getString(TOAST);
                    notifyConnectionLost(address, message);
                    break;
            }
        }

        private void sendDataToSubscriber() {
            CallbackContext dataAvailableCallback = dataAvailableCallbacks.get(address);
            if (dataAvailableCallback == null) {
                return;
            }

            String data = readUntil(delimiter);
            if (data != null && data.length() > 0) {
                PluginResult result = new PluginResult(PluginResult.Status.OK, data);
                result.setKeepCallback(true);
                dataAvailableCallback.sendPluginResult(result);

                sendDataToSubscriber();
            }
        }

        private String readUntil(String c) {
            String data = "";
            int index = buffer.indexOf(c, 0);
            if (index > -1) {
                data = buffer.substring(0, index + c.length());
                buffer.delete(0, index + c.length());
            }
            return data;
        }

        private void sendRawDataToSubscriber(byte[] data) {
            CallbackContext dataAvailableCallback = dataAvailableCallbacksRaw.get(address);
            if (dataAvailableCallback == null) {
                return;
            }

            if (data != null && data.length > 0) {
                PluginResult result = new PluginResult(PluginResult.Status.OK, data);
                result.setKeepCallback(true);
                dataAvailableCallback.sendPluginResult(result);
            }
        }

        public void setDelimiter(String newDelimiter) {
            delimiter = newDelimiter;
        }
    };

    private void notifyConnectionLost(String macAddress, String error) {
        if (connectCallbacks.containsKey(macAddress)) {
            connectCallbacks.get(macAddress).error(error);
            connectCallbacks.remove(macAddress);
        }
    }

    private void notifyConnectionSuccess(String macAddress) {
        if (connectCallbacks.containsKey(macAddress)) {
            PluginResult result = new PluginResult(PluginResult.Status.OK);
            result.setKeepCallback(true);
            connectCallbacks.get(macAddress).sendPluginResult(result);
        }
    }

}
