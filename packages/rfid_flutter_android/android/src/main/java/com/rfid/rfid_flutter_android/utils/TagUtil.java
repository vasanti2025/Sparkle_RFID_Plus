package com.rfid.rfid_flutter_android.utils;

import com.rscja.deviceapi.entity.BarcodeEntity;
import com.rscja.deviceapi.entity.UHFTAGInfo;
import com.rscja.utility.StringUtility;

import java.util.HashMap;
import java.util.Map;

public class TagUtil {
    public static Map<String, Object> getTagMap(UHFTAGInfo tagInfo) {
        Map<String, Object> map = new HashMap<>();
        map.put("type", "RFID_TAG");
        map.put("reserved", tagInfo.getReserved());
        map.put("epc", tagInfo.getEPC());
        map.put("epcBytes", tagInfo.getEpcBytes());
        map.put("tid", tagInfo.getTid());
        map.put("tidBytes", tagInfo.getTidBytes());
        map.put("user", tagInfo.getUser());
        map.put("userBytes", tagInfo.getUserBytes());
        map.put("pc", tagInfo.getPc());
        map.put("rssi", tagInfo.getRssi());
        map.put("count", tagInfo.getCount());
        map.put("antenna", StringUtility.string2Int(tagInfo.getAnt(), 1));
        //LogUtility_qcom.myLogV("TagUtil", "Tag Map: " + map);
        return map;
    }

    public static Map<String, Object> getBarcodeMap(BarcodeEntity barcodeEntity) {
        Map<String, Object> map = new HashMap<>();
        map.put("type", "BARCODE_TAG");
        map.put("resultCode", barcodeEntity.getResultCode());
        map.put("barcode", barcodeEntity.getBarcodeData());
        map.put("barcodeData", barcodeEntity.getBarcodeBytesData());
        map.put("barcodeType", barcodeEntity.getBarcodeName());
        map.put("decodeTime", barcodeEntity.getDecodeTime());
        //LogUtility_qcom.myLogV("TagUtil", "Barcode Map: " + map);
        return map;
    }

}
