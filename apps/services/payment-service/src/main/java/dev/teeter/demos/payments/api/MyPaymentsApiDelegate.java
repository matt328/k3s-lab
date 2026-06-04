package dev.teeter.demos.payments.api;

import java.time.OffsetDateTime;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import dev.teeter.demos.payments.model.Payment;
import dev.teeter.demos.payments.model.PaymentRequest;

@Service
public class MyPaymentsApiDelegate implements PaymentsApiDelegate {
  private static final Logger log = LoggerFactory.getLogger(MyPaymentsApiDelegate.class);

  @Override
  public Payment createPayment(PaymentRequest paymentRequest) {
    log.info("Authorizing payment for order {}", paymentRequest.getOrderId());

    Payment payment = new Payment();
    payment.setId("payment-" + paymentRequest.getOrderId());
    payment.setOrderId(paymentRequest.getOrderId());
    payment.setAmount(paymentRequest.getAmount());
    payment.status(Payment.StatusEnum.SUCCESS);
    payment.setCreatedAt(OffsetDateTime.now());
    payment.setUpdatedAt(OffsetDateTime.now());
    return payment;
  }

  @Override
  public Payment getPayment(String id) {
    log.info("Returning payment {}", id);

    Payment payment = new Payment();
    payment.setId(id);
    payment.setOrderId("order-" + id);
    payment.setAmount(19.99f);
    payment.status(Payment.StatusEnum.SUCCESS);
    payment.setCreatedAt(OffsetDateTime.now());
    payment.setUpdatedAt(OffsetDateTime.now());
    return payment;
  }
}
