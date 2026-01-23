// Frida script to extract WeChat database encryption key
// Usage: frida -U -f com.tencent.mm -l extract-key.js --no-pause

Java.perform(function() {
    var SQLiteDatabase = Java.use("com.tencent.wcdb.database.SQLiteDatabase");

    SQLiteDatabase.openDatabase.overload(
        'java.lang.String',
        '[B',
        'com.tencent.wcdb.database.SQLiteCipherSpec',
        'com.tencent.wcdb.database.SQLiteDatabase$CursorFactory',
        'int',
        'com.tencent.wcdb.DatabaseErrorHandler',
        'int'
    ).implementation = function(path, password, cipherSpec, factory, flags, errorHandler, poolSize) {
        if (path && path.indexOf("EnMicroMsg.db") !== -1) {
            var key = "";
            if (password) {
                for (var i = 0; i < password.length; i++) {
                    key += String.fromCharCode(password[i]);
                }
            }
            // Output in parseable format
            console.log("WECHAT_KEY=" + key);
            console.log("WECHAT_DB_PATH=" + path);
        }
        return this.openDatabase(path, password, cipherSpec, factory, flags, errorHandler, poolSize);
    };
});
