class Plans {
  static const String free = 'free';
  static const String basic = 'basic';       // Старт
  static const String pro = 'pro';           // Про
  static const String business = 'business'; // Бизнес
  static const String enterprise = 'enterprise';          // Корпорат
  static const String enterprisePlus = 'enterprise_plus'; // Макс

  static const List<String> all = [free, basic, pro, business, enterprise, enterprisePlus];

  // Лимит активных людей (уволенные не считаются)
  static const Map<String, int> peopleLimitByPlan = {
    free: 3,
    basic: 15,
    pro: 30,
    business: 100,
    enterprise: 300,
    enterprisePlus: 500,
  };

  // GPS-трекинг доступен только с Про и выше
  static const Map<String, bool> gpsEnabledByPlan = {
    free: false,
    basic: false,
    pro: true,
    business: true,
    enterprise: true,
    enterprisePlus: true,
  };

  static String uiName(String plan) {
    switch (plan) {
      case basic:        return 'Старт';
      case pro:          return 'Про';
      case business:     return 'Бизнес';
      case enterprise:   return 'Корпорат';
      case enterprisePlus: return 'Макс';
      default:           return 'Free';
    }
  }

  // Цена в USD / месяц — Google Play Billing конвертирует в локальную валюту автоматически
  static const Map<String, int> priceUsdByPlan = {
    free: 0,
    basic: 12,
    pro: 24,
    business: 42,
    enterprise: 69,
    enterprisePlus: 99,
  };

  // Цена в PLN / месяц (нетто, без НДС)
  static const Map<String, int> pricePlnByPlan = {
    free: 0,
    basic: 49,
    pro: 99,
    business: 179,
    enterprise: 299,
    enterprisePlus: 399,
  };

  static int peopleLimit(String? plan) =>
      peopleLimitByPlan[plan ?? free] ?? peopleLimitByPlan[free]!;

  static int priceUsd(String? plan) =>
      priceUsdByPlan[plan ?? free] ?? priceUsdByPlan[free]!;

  static int pricePln(String? plan) =>
      pricePlnByPlan[plan ?? free] ?? pricePlnByPlan[free]!;

  static bool gpsEnabled(String? plan) =>
      gpsEnabledByPlan[plan ?? free] ?? false;
}
