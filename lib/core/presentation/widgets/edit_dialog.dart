import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/intake_card.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/generated/l10n.dart';

class EditDialog extends StatefulWidget {
  final IntakeEntity intakeEntity;
  final bool usesImperialUnits;

  const EditDialog({
    super.key,
    required this.intakeEntity,
    required this.usesImperialUnits,
  });

  @override
  State<StatefulWidget> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late TextEditingController amountEditingController;

  /// Grams per serving when the intake was logged in servings, else null.
  double? get _servingSize => intakeServingCount(widget.intakeEntity) == null
      ? null
      : widget.intakeEntity.meal.servingQuantity;

  @override
  void initState() {
    super.initState();
    // Logged in servings: edit in servings, the way it was logged.
    final servings = intakeServingCount(widget.intakeEntity);
    double initialAmount =
        servings ??
        _convertValue(
          widget.intakeEntity.amount,
          widget.intakeEntity.meal.mealUnit,
        );
    amountEditingController = TextEditingController(
      text: initialAmount.toStringAsFixed(2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).editItemDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: amountEditingController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: S.of(context).quantityLabel,
              suffixText: _servingSize == null
                  ? _convertUnit(widget.intakeEntity.meal.mealUnit ?? '')
                  : S
                        .of(context)
                        .measureUnitServing(
                          double.tryParse(
                                amountEditingController.text.replaceAll(
                                  ',',
                                  '.',
                                ),
                              ) ??
                              1,
                        ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            final newAmount = double.tryParse(
              amountEditingController.text.replaceAll(',', '.'),
            );
            if (newAmount == null) return;
            final servingSize = _servingSize;
            if (servingSize != null) {
              // The caller stores grams; servings are amount / serving size.
              Navigator.of(context).pop(newAmount * servingSize);
              return;
            }
            Navigator.of(context).pop(
              _convertBackToMetricValue(
                newAmount,
                widget.intakeEntity.meal.mealUnit,
              ),
            );
          },
          child: Text(S.of(context).dialogOKLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(S.of(context).dialogCancelLabel),
        ),
      ],
    );
  }

  double _convertValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.gToOz(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.mlToFlOz(value) : value;
      default:
        return value;
    }
  }

  double _convertBackToMetricValue(double value, String? unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? UnitCalc.ozToG(value) : value;
      case 'ml':
        return widget.usesImperialUnits ? UnitCalc.flOzToMl(value) : value;
      default:
        return value;
    }
  }

  String _convertUnit(String unit) {
    switch (unit) {
      case 'g':
        return widget.usesImperialUnits ? 'oz' : 'g';
      case 'ml':
        return widget.usesImperialUnits ? 'fl.oz' : 'ml';
      default:
        return unit;
    }
  }
}
