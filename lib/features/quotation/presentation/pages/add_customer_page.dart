import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/locale/oq_text.dart';
import '../../../../core/location/country_state_service.dart';
import '../../../../core/session/app_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_record.dart';

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({super.key});

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _pan = TextEditingController();
  final _gst = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();

  static final _emailPattern = RegExp(
    r'^[a-zA-Z0-9_+&*-]+(?:\.[a-zA-Z0-9_+&*-]+)*@(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$',
  );
  static final _panPattern = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final _gstPattern = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9][A-Z][0-9]$',
  );

  List<String> _countries = const [];
  List<String> _states = const [];
  List<({int id, String name})> _branches = const [];
  String? _country;
  String? _state;
  int? _branchId;
  var _loadingCountries = true;
  var _loadingBranches = true;
  var _loadingStates = false;
  var _saving = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _loadCountries();
    _loadBranches();
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _pan.dispose();
    _gst.dispose();
    _street.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final clientCode = AppSession.clientCode;
    if (clientCode.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingBranches = false);
      return;
    }
    final result = await Injection.quotations.loadBranches(clientCode);
    if (!mounted) return;
    final branches = switch (result) {
      Success(:final data) => [...data],
      Error() => <({int id, String name})>[],
    };
    final loginId = AppSession.branchId;
    if (loginId > 0 && !branches.any((branch) => branch.id == loginId)) {
      final name = AppSession.branchName.isEmpty ? tr('Branch') : AppSession.branchName;
      branches.insert(0, (id: loginId, name: name));
    }
    setState(() {
      _branches = branches;
      _branchId = _defaultBranchId(branches);
      _loadingBranches = false;
    });
  }

  int? _defaultBranchId(List<({int id, String name})> branches) {
    final loginId = AppSession.branchId;
    for (final branch in branches) {
      if (branch.id == loginId) return branch.id;
    }
    final loginName = AppSession.branchName.trim().toLowerCase();
    if (loginName.isNotEmpty) {
      for (final branch in branches) {
        if (branch.name.trim().toLowerCase() == loginName) return branch.id;
      }
    }
    return branches.isEmpty ? null : branches.first.id;
  }

  Future<void> _loadCountries() async {
    setState(() {
      _loadingCountries = true;
      _locationError = null;
    });
    try {
      final countries = await CountryStateService.fetchCountries();
      if (!mounted) return;
      final preferred = countries.contains('India')
          ? 'India'
          : (countries.isEmpty ? null : countries.first);
      setState(() {
        _countries = countries;
        _country = preferred;
        _loadingCountries = false;
        _locationError = countries.isEmpty ? 'Countries could not be loaded' : null;
      });
      if (preferred != null) await _loadStates(preferred);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCountries = false;
        _locationError = 'Countries could not be loaded';
      });
    }
  }

  Future<void> _loadStates(String country) async {
    setState(() {
      _loadingStates = true;
      _states = const [];
      _state = null;
    });
    try {
      final states = await CountryStateService.fetchStates(country);
      if (!mounted) return;
      setState(() {
        _states = states;
        _loadingStates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _states = const [];
        _state = null;
        _loadingStates = false;
      });
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    _name.clear();
    _mobile.clear();
    _email.clear();
    _pan.clear();
    _gst.clear();
    _street.clear();
    _city.clear();
    final preferred = _countries.contains('India')
        ? 'India'
        : (_countries.isEmpty ? null : _countries.first);
    setState(() {
      _country = preferred;
      _state = null;
      _branchId = _defaultBranchId(_branches);
    });
    if (preferred != null) _loadStates(preferred);
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return tr('Customer name is required');
    if (name.length < 2 || RegExp(r'\d').hasMatch(name)) {
      return tr('Enter a valid customer name');
    }
    return null;
  }

  String? _validateMobile(String? value) {
    final mobile = value?.trim() ?? '';
    if (mobile.isEmpty) return tr('Mobile number is required');
    if (!RegExp(r'^\d+$').hasMatch(mobile)) return tr('Enter a valid mobile number');
    if ((_country ?? '') == 'India') {
      if (mobile.length != 10) return tr('Enter a 10-digit mobile number');
    } else if (mobile.length < 6 || mobile.length > 15) {
      return tr('Enter a valid mobile number');
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (!email.contains('@') || !_emailPattern.hasMatch(email)) {
      return tr('Enter a valid email');
    }
    return null;
  }

  String? _validatePan(String? value) {
    final pan = value?.trim().toUpperCase() ?? '';
    if (pan.isEmpty) return null;
    if (!_panPattern.hasMatch(pan)) return tr('Enter a valid PAN number');
    return null;
  }

  String? _validateGst(String? value) {
    final gst = value?.trim().toUpperCase() ?? '';
    if (gst.isEmpty) return null;
    if (!_gstPattern.hasMatch(gst)) return tr('Enter a valid GST number');
    return null;
  }

  String? _validateStreet(String? value) {
    final street = value?.trim() ?? '';
    if (street.isEmpty) return null;
    if (street.length < 3) return tr('Enter a valid street');
    return null;
  }

  String? _validateCity(String? value) {
    final city = value?.trim() ?? '';
    if (city.isEmpty) return tr('City is required');
    if (city.length < 2 || RegExp(r'\d').hasMatch(city)) return tr('Enter a valid city');
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (_country == null || _country!.isEmpty) {
      setState(() => _locationError = tr('Select a country'));
      return;
    }
    if (!valid) return;
    final clientCode = AppSession.clientCode;
    if (clientCode.isEmpty) {
      _message(tr('Sign in again to add a customer'));
      return;
    }
    setState(() => _saving = true);
    final name = _name.text.trim();
    final mobile = _mobile.text.trim();
    final email = _email.text.trim();
    final result = await Injection.quotations.addCustomer(
      clientCode: clientCode,
      name: name,
      mobile: mobile,
      email: email,
      pan: _pan.text.trim().toUpperCase(),
      gst: _gst.text.trim().toUpperCase(),
      street: _street.text.trim(),
      city: _city.text.trim(),
      state: _state?.trim() ?? '',
      country: _country!.trim(),
      branchId: _branchId ?? 0,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Success<CustomerRecord>(:final data):
        Navigator.pop(context, data);
      case Error<CustomerRecord>(:final failure):
        _message(failure.message);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return OrderQuotationScope(
      child: Scaffold(
      backgroundColor: AppColors.homeSurface,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        foregroundColor: Colors.white,
        title: Text(tr('Add Customer')),
        actions: const [LanguageButton(light: true)],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _field(
              controller: _name,
              hint: tr('Customer Name'),
              validator: _validateName,
              textCapitalization: TextCapitalization.words,
            ),
            _field(
              controller: _mobile,
              hint: tr('Mobile Number'),
              validator: _validateMobile,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_country == 'India' ? 10 : 15),
              ],
            ),
            _field(
              controller: _email,
              hint: tr('Email'),
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
            ),
            _field(
              controller: _pan,
              hint: tr('PAN Number'),
              validator: _validatePan,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(10),
                _UpperCaseFormatter(),
              ],
            ),
            _field(
              controller: _gst,
              hint: tr('GST Number'),
              validator: _validateGst,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(15),
                _UpperCaseFormatter(),
              ],
            ),
            _field(
              controller: _street,
              hint: tr('Street'),
              validator: _validateStreet,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _countryBox()),
                const SizedBox(width: 12),
                Expanded(child: _stateBox()),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              controller: _city,
              hint: tr('City'),
              validator: _validateCity,
              textCapitalization: TextCapitalization.words,
            ),
            _branchBox(),
            if (_locationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _locationError!,
                  style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(_saving ? tr('Saving') : tr('Add Customer')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _reset,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8A8680),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(tr('Reset')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        style: const TextStyle(color: AppColors.charcoal, fontSize: 15),
        decoration: _decoration(hint),
      ),
    );
  }

  Widget _branchBox() {
    final selected = _branches.any((branch) => branch.id == _branchId) ? _branchId : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        key: ValueKey('branch-$selected-${_branches.length}-$_loadingBranches'),
        initialValue: selected,
        isExpanded: true,
        hint: Text(_loadingBranches ? tr('Loading') : tr('Branch')),
        items: [
          for (final branch in _branches)
            DropdownMenuItem(
              value: branch.id,
              child: Text(branch.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _loadingBranches ? null : (value) => setState(() => _branchId = value),
        validator: (value) => value == null ? tr('Select a branch') : null,
        decoration: _decoration(tr('Branch')),
      ),
    );
  }

  Widget _countryBox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('country-${_country ?? ''}-${_countries.length}'),
        initialValue: _countries.contains(_country) ? _country : null,
        isExpanded: true,
        hint: Text(_loadingCountries ? tr('Loading') : tr('Country')),
        items: [
          for (final country in _countries)
            DropdownMenuItem(value: country, child: Text(country, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _loadingCountries
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  _country = value;
                  _locationError = null;
                });
                _loadStates(value);
              },
        decoration: _decoration('Country'),
      ),
    );
  }

  Widget _stateBox() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('state-${_state ?? ''}-${_states.length}-$_loadingStates'),
        initialValue: _states.contains(_state) ? _state : null,
        isExpanded: true,
        hint: Text(_loadingStates ? tr('Loading') : tr('Select state')),
        items: [
          for (final state in _states)
            DropdownMenuItem(value: state, child: Text(state, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _loadingStates
            ? null
            : (value) => setState(() => _state = value),
        decoration: _decoration('Select state'),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9A958C)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.goldText),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
