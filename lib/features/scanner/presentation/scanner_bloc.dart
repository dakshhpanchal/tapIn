import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/off_unavailable_exception.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';

part 'scanner_event.dart';

part 'scanner_state.dart';

/// What a failed lookup means to the person scanning, so the screen can say
/// something more useful than "error".
ScannerFailedStateType _failureTypeOf(Object exception) {
  if (exception is ProductNotFoundException) {
    return ScannerFailedStateType.productNotFound;
  }
  if (exception is OffUnavailableException) return ScannerFailedStateType.busy;
  if (exception is SocketException ||
      exception is http.ClientException ||
      exception is TimeoutException) {
    return ScannerFailedStateType.offline;
  }
  return ScannerFailedStateType.error;
}

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final SearchProductByBarcodeUseCase _searchProductUseCase;
  final GetConfigUsecase _getConfigUsecase;

  ScannerBloc(this._searchProductUseCase, this._getConfigUsecase)
    : super(ScannerInitial()) {
    on<ScannerLoadProductEvent>((event, emit) async {
      emit(ScannerLoadingState());

      try {
        final meal = await _searchProductUseCase.searchProductByBarcode(
          event.barcode,
        );
        final config = await _getConfigUsecase.getConfig();
        emit(
          ScannerLoadedState(
            product: meal,
            usesImperialUnits: config.usesImperialFoodUnits,
          ),
        );
      } catch (exception) {
        emit(ScannerFailedState(_failureTypeOf(exception)));
      }
    });
  }
}
