import 'package:flutter/material.dart';

import 'app_navigator.dart' as app_nav;
import 'main_customer.dart' as customer;

final GlobalKey<NavigatorState> navigatorKey = app_nav.navigatorKey;

void main() => customer.main();
