package com.example;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Service
public class EventProducer {

    private final KafkaProducer<String, String> producer;

    public EventProducer(KafkaProducer<String, String> producer) {
        this.producer = producer;
    }

    public void sendOrderEvent(String orderId) {
        ProducerRecord<String, String> record = new ProducerRecord<>("order-topic", orderId);
        producer.send(record);
    }

    @KafkaListener(topics = "payment-topic")
    public void handlePaymentEvent(String message) {
        System.out.println("Payment received: " + message);
    }
}
