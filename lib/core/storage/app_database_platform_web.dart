import 'package:sembast_web/sembast_web.dart';

/// Opens the database in IndexedDB (web).
Future<Database> openPlatformDatabase(String fileName) =>
    databaseFactoryWeb.openDatabase(fileName);
