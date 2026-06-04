package dev.teeter.demos.orders.api;

import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import dev.teeter.demos.orders.model.Order;
import dev.teeter.demos.payments.api.PaymentsApi;
import dev.teeter.demos.payments.model.Payment;
import dev.teeter.demos.payments.model.PaymentRequest;

@Service
public class MyOrdersApiDelegate implements OrdersApiDelegate {
  private static final Logger log = LoggerFactory.getLogger(MyOrdersApiDelegate.class);

  private final PaymentsApi paymentsApi;

  public MyOrdersApiDelegate(PaymentsApi paymentsApi) {
    this.paymentsApi = paymentsApi;
  }

  @Override
  public Order ordersIdGet(String id) {
    PaymentRequest paymentRequest = new PaymentRequest();
    paymentRequest.setOrderId(id);
    paymentRequest.setAmount(19.99f);
    paymentRequest.setMethod(PaymentRequest.MethodEnum.CREDIT_CARD);

    Payment payment = paymentsApi.createPayment(paymentRequest);
    log.info("Returning order {} after payment {}", id, payment.getId());

    Order order = new Order();
    order.setId(id);
    order.status(Order.StatusEnum.CONFIRMED);
    return order;
  }

}
